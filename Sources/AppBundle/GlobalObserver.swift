import AppKit
import Common

enum GlobalObserver {
    private static func onNotif(_ notification: Notification) {
        // Third line of defence against lock screen window. See: closedWindowsCache
        // Second and third lines of defence are technically needed only to avoid potential flickering
        let nsApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if nsApp?.bundleIdentifier == lockScreenAppBundleId {
            return
        }
        let pid = nsApp?.processIdentifier
        let notifName = notification.name.rawValue
        Task.startUnstructured { @MainActor in
            if let pid { noteAppEvent(notifName, pid: pid) }
            if !TrayMenuModel.shared.isEnabled { return }
            if notifName == NSWorkspace.didActivateApplicationNotification.rawValue {
                scheduleCancellableCompleteRefreshSession(.globalObserver(notifName), optimisticallyPreLayoutWorkspaces: true)
            } else {
                scheduleCancellableCompleteRefreshSession(.globalObserver(notifName))
            }
        }
    }

    /// Keeps the knowledge about the running apps up to date without enumerating all of them on every refresh
    @MainActor
    private static func noteAppEvent(_ notifName: String, pid: pid_t) {
        switch notifName {
            case NSWorkspace.didLaunchApplicationNotification.rawValue:
                forgetActivationPolicy(of: pid) // The pid may be reused
                runningAppsScanSchedule.appsMayHaveChanged()
            case NSWorkspace.didTerminateApplicationNotification.rawValue:
                forgetActivationPolicy(of: pid) // The pid may be reused. Registered apps are destroyed by the refresh
            default: // Activated or unhidden
                // A process that isn't registered gets activated: it may have switched to the regular activation
                // policy. Activations of registered apps happen all the time and don't change the set of apps
                if MacApp.allAppsMap[pid] == nil {
                    forgetActivationPolicy(of: pid)
                    runningAppsScanSchedule.appsMayHaveChanged()
                }
        }
    }

    private static func onHideApp(_ notification: Notification) {
        let notifName = notification.name.rawValue
        Task.startUnstructured { @MainActor in
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            try await runLightSession(.globalObserver(notifName), token) {
                if config.automaticallyUnhideMacosHiddenApps {
                    if let w = prevFocus?.windowOrNil,
                       w.macAppUnsafe.nsApp.isHidden,
                       // "Hide others" (cmd-alt-h) -> don't force focus
                       // "Hide app" (cmd-h) -> force focus
                       MacApp.allAppsMap.values.count(where: { $0.nsApp.isHidden }) == 1
                    {
                        // Force focus
                        _ = w.focusWindow()
                        w.nativeFocus()
                    }
                    for app in MacApp.allAppsMap.values {
                        app.nsApp.unhide()
                    }
                }
            }
        }
    }

    @MainActor
    static func initObserver() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main, using: onHideApp)
        nc.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main, using: onNotif)

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            // todo reduce number of refreshSession in the callback
            //  resetManipulatedWithMouseIfPossible might call its own refreshSession
            //  The end of the callback calls refreshSession
            Task.startUnstructured { @MainActor in
                try await resetManipulatedWithMouseIfPossible()
                let mouseLocation = mouseLocation
                let clickedMonitor = mouseLocation.monitorApproximation
                switch true {
                    // Detect clicks on desktop of different monitors
                    case clickedMonitor.visibleRect.contains(mouseLocation) && clickedMonitor.visibleWorkspace != globalFocus.workspace:
                        _ = try await runLightSession(.globalObserverLeftMouseUp, token) {
                            clickedMonitor.visibleWorkspace.focusWorkspace()
                        }
                    // Detect close button clicks for unfocused windows. Yes, kAXUIElementDestroyedNotification is that unreliable
                    //  And trigger new window detection that could be delayed due to mouseDown event
                    default:
                        scheduleCancellableCompleteRefreshSession(.globalObserverLeftMouseUp)
                }
            }
        }
    }
}
