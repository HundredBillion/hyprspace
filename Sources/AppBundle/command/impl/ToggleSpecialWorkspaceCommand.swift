import AppKit
import Common

/// Hyprland-like special workspace (scratchpad).
///
/// macOS doesn't allow to show two workspaces on top of each other, so the overlay is emulated:
/// windows of the special workspace are shown as pinned floating windows on top of the current workspace.
/// When the special workspace is hidden, the windows go back to their (invisible) special workspace
struct ToggleSpecialWorkspaceCommand: Command {
    let args: ToggleSpecialWorkspaceCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        let specialName = args.workspaceName
        let special = Workspace.get(byName: specialName)
        let currentWorkspace = target.workspace
        if currentWorkspace == special {
            return .fail(io.err("The special workspace is focused as a regular workspace. Switch to another workspace first"))
        }

        let shown = Workspace.all
            .flatMap { $0.floatingWindowsContainer.children.filterIsInstance(of: Window.self) }
            .filter { $0.shownSpecialWorkspace == specialName }
        if !shown.isEmpty { // Hide
            for window in shown {
                // Binding to a tiling container clears 'isPinned' and 'shownSpecialWorkspace'
                window.bind(to: special.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            }
            return .from(bool: currentWorkspace.focusWorkspace())
        }

        let hidden = special.allLeafWindowsRecursive.filter { $0.lifeStatus.isInhabited }
        let specialMru = special.mostRecentWindowRecursive
        guard let mostRecent = hidden.first(where: { $0 == specialMru }) ?? hidden.last else {
            return .fail(io.err("Special workspace '\(specialName)' is empty. Move a window there first: movetoworkspacesilent special"))
        }
        let slots = specialWorkspaceSlots(currentWorkspace.workspaceMonitorInfo.visibleRect, count: hidden.count)
        for (window, slot) in zip(hidden, slots) {
            window.bindAsFloatingWindow(to: currentWorkspace)
            window.shownSpecialWorkspace = specialName
            window.isPinned = true // Follow the monitor across workspace switches, like Hyprland does
            window.lastFloatingSize = slot.size
            // The window was hidden in the corner of the screen together with the special workspace.
            // Forget about it, otherwise the next layout pass moves the window back to where it was before hiding
            window.forgetHiddenInCornerPosition()
            window.setAxFrame(slot.topLeftCorner, slot.size)
            window.lastKnownFloatingRect = slot
            if window != mostRecent { window.raiseWithoutFocus() } // Raise above the tiling windows
        }
        return .from(bool: mostRecent.focusWindow())
    }
}

/// Windows of the special workspace are placed side by side in the centered area of the monitor
func specialWorkspaceSlots(_ monitor: Rect, count: Int, scale: CGFloat = 0.8, gap: CGFloat = 10) -> [Rect] {
    if count <= 0 { return [] }
    let width = monitor.width * scale
    let height = monitor.height * scale
    let x = monitor.topLeftX + (monitor.width - width) / 2
    let y = monitor.topLeftY + (monitor.height - height) / 2
    let slotWidth = (width - gap * CGFloat(count - 1)) / CGFloat(count)
    return (0 ..< count).map { i in
        Rect(topLeftX: x + (slotWidth + gap) * CGFloat(i), topLeftY: y, width: slotWidth, height: height)
    }
}
