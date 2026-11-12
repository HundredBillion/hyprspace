import AppKit
import Common

final class MacWindow: Window {
    let macApp: MacApp
    private var prevUnhiddenProportionalPositionInsideWorkspaceRect: CGPoint?

    @MainActor private init(
        _ id: OpaqueWindowId,
        _ actor: MacApp,
        lastFloatingSize: CGSize?,
        parent: NonLeafTreeNodeObject,
        adaptiveWeight: CGFloat,
        index: Int,
    ) {
        self.macApp = actor
        super.init(id: id, actor, lastFloatingSize: lastFloatingSize, parent: parent, adaptiveWeight: adaptiveWeight, index: index)
    }

    @MainActor static var allWindowsMap: [OpaqueWindowId: MacWindow] = [:]
    @MainActor static var allWindows: [MacWindow] { Array(allWindowsMap.values) }

    @MainActor
    @discardableResult
    static func getOrRegister(windowId: OpaqueWindowId, macApp: MacApp) async throws -> MacWindow {
        if let existing = allWindowsMap[windowId] { return existing }
        let rect = try await macApp.getAxRect(windowId, .cancellable)
        let workspace = isStartup
            ? (rect?.center.monitorApproximation ?? mainMonitorInfo).visibleWorkspace
            : globalFocus.workspace
        let windowLevel = try await macApp.getWindowLevel(windowId, .cancellable)
        let windowType = try await macApp.getAxUiElementWindowType(windowId, windowLevel, .cancellable)

        // atomic synchronous section
        if let existing = allWindowsMap[windowId] { return existing }
        // Computing the binding data may restructure the tree, that's why it must stay inside the atomic section
        let data = unbindAndGetBindingData(windowType, workspace, window: nil)
        let window = MacWindow(windowId, macApp, lastFloatingSize: rect?.size, parent: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
        allWindowsMap[windowId] = window

        try await debugWindowsIfRecording(window, .cancellable)
        if try await !restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window) {
            await runOnWindowDetected(ifConventional: window)
        }
        return window
    }

    // var description: String {
    //     let description = [
    //         ("title", title),
    //         ("role", axWindow.get(Ax.roleAttr)),
    //         ("subrole", axWindow.get(Ax.subroleAttr)),
    //         ("identifier", axWindow.get(Ax.identifierAttr)),
    //         ("modal", axWindow.get(Ax.modalAttr).map { String($0) } ?? ""),
    //         ("windowId", String(windowId)),
    //     ].map { "\($0.0): '\(String(describing: $0.1))'" }.joined(separator: ", ")
    //     return "Window(\(description))"
    // }

    func isWindowHeuristic(_ windowLevel: MacOsWindowLevel?, _ cm: CancellationMode) async throws -> Bool { // todo cache
        try await macApp.isWindowHeuristic(windowId, windowLevel, cm)
    }

    func isDialogHeuristic(_ windowLevel: MacOsWindowLevel?, _ cm: CancellationMode) async throws -> Bool { // todo cache
        try await macApp.isDialogHeuristic(windowId, windowLevel, cm)
    }

    func dumpAxInfo(_ cm: CancellationMode) async throws -> [String: Json] {
        try await macApp.dumpWindowAxInfo(windowId: windowId, cm)
    }

    @MainActor func getWindowLevel(_ cm: CancellationMode) async throws -> MacOsWindowLevel? {
        try await macApp.getWindowLevel(windowId, cm)
    }

    func setNativeFullscreen(_ value: Bool) {
        macApp.setNativeFullscreen(windowId, value)
    }

    func setNativeMinimized(_ value: Bool) {
        macApp.setNativeMinimized(windowId, value)
    }

    // skipClosedWindowsCache is an optimization when it's definitely not necessary to cache closed window.
    //                        If you are unsure, it's better to pass `false`
    @MainActor
    func garbageCollect(skipClosedWindowsCache: Bool) {
        if MacWindow.allWindowsMap.removeValue(forKey: windowId) == nil {
            return
        }
        if !skipClosedWindowsCache { cacheClosedWindowIfNeeded() }
        let parent = unbindFromParent().parent
        let deadWindowWorkspace = parent.nodeWorkspace
        if let deadWindowWorkspace { preferPreviouslyFocusedWindow(in: deadWindowWorkspace, closedWindowId: windowId) }
        let focus = globalFocus
        if let deadWindowWorkspace, deadWindowWorkspace == focus.workspace ||
            deadWindowWorkspace == prevFocusedWorkspace && prevFocusedWorkspaceDate.distance(to: .now) < 1
        {
            switch parent.cases {
                case .tilingContainer, .floatingWindowsContainer, .macosHiddenAppsWindowsContainer, .macosFullscreenWindowsContainer:
                    let deadWindowFocus = deadWindowWorkspace.toLiveFocus()
                    _ = setFocus(to: deadWindowFocus)
                    // Guard against "Apple Reminders popup" bug: upstream issue #201
                    if focus.windowOrNil?.app.pid != app.pid {
                        // Force focus to fix macOS annoyance with focused apps without windows.
                        //   upstream issue #65
                        deadWindowFocus.windowOrNil?.nativeFocus()
                    }
                case .macosPopupWindowsContainer, // Don't switch back on popup destruction
                     .workspace, // Workspace is invalid parent for windows
                     .monitor, // Monitor is invalid parent for windows
                     .workspacesContainer, // WorkspacesContainer is invalid parent for windows
                     .macosMinimizedWindowsContainer: // Don't switch back on minimized windows destruction
                    break
            }
        }
    }

    override func getTitle(_ cm: CancellationMode) async throws -> String { try await macApp.getAxTitle(windowId, cm) ?? "" }

    override func isMacosFullscreen(_ cm: CancellationMode) async throws -> Bool { try await macApp.isMacosNativeFullscreen(windowId, cm) == true }
    override func isMacosMinimized(_ cm: CancellationMode) async throws -> Bool { try await macApp.isMacosNativeMinimized(windowId, cm) == true }
    override func getMacosWindowNativeState(_ cm: CancellationMode) async throws -> MacosWindowNativeState {
        try await macApp.getMacosWindowNativeState(windowId, cm) ?? .normal
    }

    @MainActor override func nativeFocus() {
        macApp.nativeFocus(windowId)
    }

    override func closeAxWindow() {
        garbageCollect(skipClosedWindowsCache: true)
        macApp.closeAndUnregisterAxWindow(windowId)
    }

    // todo it's part of the window layout and should be moved to layoutRecursive.swift
    @MainActor
    func hideInCorner(_ corner: OptimalHideCorner) async throws {
        guard let nodeMonitorInfo else { return }
        // Don't accidentally override prevUnhiddenEmulationPosition in case of subsequent `hideInCorner` calls
        if !isHiddenInCorner {
            guard let windowRect = try await getAxRect(.cancellable) else { return }
            // Check for isHiddenInCorner for the second time because of the suspension point above
            if !isHiddenInCorner {
                let topLeftCorner = windowRect.topLeftCorner
                let monitorRect = windowRect.center.monitorApproximation.rect // Similar to layoutFloatingWindow. Non idempotent
                let absolutePoint = topLeftCorner - monitorRect.topLeftCorner
                prevUnhiddenProportionalPositionInsideWorkspaceRect =
                    CGPoint(x: absolutePoint.x / monitorRect.width, y: absolutePoint.y / monitorRect.height)
                if isFloating {
                    lastFloatingSize = windowRect.size
                }
            }
        }
        let p: CGPoint
        switch corner {
            case .bottomLeftCorner:
                guard let s = try await getAxSize(.cancellable) else { fallthrough }
                // Zoom will jump off if you do one pixel offset upstream issue #527
                // todo this ad hoc won't be necessary once I implement optimization suggested by Zalim
                let onePixelOffset = macApp.appId == .zoom ? .zero : CGPoint(x: 1, y: -1)
                p = nodeMonitorInfo.visibleRect.bottomLeftCorner + onePixelOffset + CGPoint(x: -s.width, y: 0)
            case .bottomRightCorner:
                // Zoom will jump off if you do one pixel offset upstream issue #527
                // todo this ad hoc won't be necessary once I implement optimization suggested by Zalim
                let onePixelOffset = macApp.appId == .zoom ? .zero : CGPoint(x: 1, y: 1)
                p = nodeMonitorInfo.visibleRect.bottomRightCorner - onePixelOffset
        }
        setAxFrame(p, nil)
    }

    @MainActor
    func unhideFromCorner() {
        guard let prevUnhiddenProportionalPositionInsideWorkspaceRect else { return }
        guard let nodeWorkspace else { return } // hiding only makes sense for workspace windows
        guard let parent else { return }

        switch getChildParentRelation(child: self, parent: parent) {
            // Just a small optimization to avoid unnecessary AX calls for non floating windows
            // Tiling windows should be unhidden with layoutRecursive anyway
            case .floatingWindow:
                let workspaceRect = nodeWorkspace.workspaceMonitorInfo.rect
                var newX = workspaceRect.topLeftX + workspaceRect.width * prevUnhiddenProportionalPositionInsideWorkspaceRect.x
                var newY = workspaceRect.topLeftY + workspaceRect.height * prevUnhiddenProportionalPositionInsideWorkspaceRect.y
                // todo we probably should replace lastFloatingSize with proper floating window sizing
                // upstream issue #1519
                let windowWidth = lastFloatingSize?.width ?? 0
                let windowHeight = lastFloatingSize?.height ?? 0
                newX = newX.coerce(in: workspaceRect.minX ... max(workspaceRect.minX, workspaceRect.maxX - windowWidth))
                newY = newY.coerce(in: workspaceRect.minY ... max(workspaceRect.minY, workspaceRect.maxY - windowHeight))

                setAxFrame(CGPoint(x: newX, y: newY), nil)
            case .macosNativeFullscreenWindow, .macosNativeHiddenAppWindow, .macosNativeMinimizedWindow,
                 .macosPopupWindow, .tiling, .rootTilingContainer, .shimContainerRelation: break
        }

        self.prevUnhiddenProportionalPositionInsideWorkspaceRect = nil
    }

    @MainActor override func forgetHiddenInCornerPosition() {
        prevUnhiddenProportionalPositionInsideWorkspaceRect = nil
    }

    @MainActor override func raiseWithoutFocus() {
        macApp.raiseWithoutFocus(windowId)
    }

    override var isHiddenInCorner: Bool {
        prevUnhiddenProportionalPositionInsideWorkspaceRect != nil
    }

    override func getAxSize(_ cm: CancellationMode) async throws -> CGSize? {
        try await macApp.getAxSize(windowId, cm)
    }

    @MainActor override func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) {
        cancelWindowAnimation(windowId) // An explicit frame always wins over a running animation
        macApp.setAxFrame(windowId, topLeft, size)
    }

    @MainActor override func setAxFrameForAnimationStep(_ topLeft: CGPoint?, _ size: CGSize?, isIntermediate: Bool, completion: @escaping @Sendable () -> ()) {
        macApp.setAxFrame(windowId, topLeft, size, intermediateAnimationStep: isIntermediate, completion: completion)
    }

    override func getAxRect(_ cm: CancellationMode) async throws -> Rect? {
        try await macApp.getAxRect(windowId, cm)
    }
}

extension Window {
    @MainActor
    func relayoutWindow(on workspace: Workspace, _ cm: CancellationMode, forceTile: Bool = false) async throws {
        let data = forceTile
            ? unbindAndGetBindingDataForNewTilingWindow(workspace, window: self)
            : try await unbindAndGetBindingDataForNewWindow(self.asMacWindow().windowId, self.asMacWindow().macApp, workspace, window: self, cm)
        bind(to: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
    }
}

// The function is private because it's unsafe. It leaves the window in unbound state
@MainActor
private func unbindAndGetBindingDataForNewWindow(_ windowId: OpaqueWindowId, _ macApp: MacApp, _ workspace: Workspace, window: Window?, _ cm: CancellationMode) async throws -> BindingData {
    let windowLevel = try await macApp.getWindowLevel(windowId, cm)
    return unbindAndGetBindingData(try await macApp.getAxUiElementWindowType(windowId, windowLevel, cm), workspace, window: window)
}

// The function is private because it's unsafe. It leaves the window in unbound state
@MainActor
private func unbindAndGetBindingData(_ windowType: AxUiElementWindowType, _ workspace: Workspace, window: Window?) -> BindingData {
    switch windowType {
        case .popup: BindingData(parent: macosPopupWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        case .dialog: BindingData(parent: workspace.floatingWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        case .window: unbindAndGetBindingDataForNewTilingWindow(workspace, window: window)
    }
}

// The function is private because it's unsafe. It leaves the window in unbound state
@MainActor
private func unbindAndGetBindingDataForNewTilingWindow(_ workspace: Workspace, window: Window?) -> BindingData {
    window?.unbindFromParent() // It's important to unbind to get correct data from below
    if config.newWindowPlacement == .master {
        return getMasterBindingData(root: workspace.rootTilingContainer)
    }
    if let (tilingParent, index) = workspace.mostRecentWindowRecursive?.nearestAliveTilingParent() {
        return switch config.newWindowPlacement {
            case .sibling: BindingData(parent: tilingParent, adaptiveWeight: WEIGHT_AUTO, index: index + 1)
            // On startup, the sizes of the windows are not known yet. Dozens of already opened windows would be
            // nested into a deep spiral, so they are laid out flat instead
            case .dwindle where isStartup: BindingData(parent: tilingParent, adaptiveWeight: WEIGHT_AUTO, index: index + 1)
            case .dwindle: getDwindleBindingData(parent: tilingParent, splitTargetIndex: index)
            case .master: dieT("Master placement is handled above")
        }
    } else {
        return BindingData(
            parent: workspace.rootTilingContainer,
            adaptiveWeight: WEIGHT_AUTO,
            index: INDEX_BIND_LAST,
        )
    }
}

/// Hyprland-like "dwindle" placement. The node at `splitTargetIndex` is split in half, and the new window takes the
/// right/bottom half. The split goes along the longer side of the node that is being split.
///
/// Side effect: the function may restructure the tree around the split target
@MainActor
private func getDwindleBindingData(parent: TilingContainer, splitTargetIndex index: Int) -> BindingData {
    let sibling = BindingData(parent: parent, adaptiveWeight: WEIGHT_AUTO, index: index + 1)
    guard parent.layout == .tiles, let target = parent.children.getOrNil(atIndex: index) else { return sibling }
    // The rect is unknown if the target hasn't been laid out yet (e.g. several windows are detected at once)
    let splitOrientation: Orientation? = target.lastAppliedLayoutPhysicalRect.map { $0.width > $0.height ? .h : .v }

    // The only window in the workspace. The root container is reused as is: its orientation comes from
    // 'default-root-container-orientation' or from an explicit 'layout' command, and dwindle must not override it
    if parent.isRootContainer && parent.inhabitedChildren.count <= 1 {
        return sibling
    }

    let splitOrientationOrDefault = splitOrientation ?? parent.orientation.opposite
    if splitOrientationOrDefault == parent.orientation {
        // Geometrically the same as wrapping the target into a nested container of the same orientation,
        // but it keeps the tree flat and plays nicely with the "opposite orientation" normalization
        let weight = target.getWeight(parent.orientation)
        target.setWeight(parent.orientation, weight / 2)
        return BindingData(parent: parent, adaptiveWeight: weight / 2, index: index + 1)
    }

    let targetBinding = target.unbindFromParent()
    let container = TilingContainer(
        parent: parent,
        adaptiveWeight: targetBinding.adaptiveWeight,
        splitOrientationOrDefault,
        .tiles,
        index: targetBinding.index,
    )
    target.bind(to: container, adaptiveWeight: WEIGHT_AUTO, index: 0)
    return BindingData(parent: container, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
}

/// Hyprland-like "master" placement. The first child of the root container is the master.
/// The last child of the root container is the stack. New windows are appended to the stack.
///
/// Side effect: the function may restructure the tree to create the stack container
@MainActor
private func getMasterBindingData(root: TilingContainer) -> BindingData {
    let last = BindingData(parent: root, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    // 0 windows: the new window becomes the master. 1 window: the new window becomes the only stack window
    guard root.layout == .tiles, root.inhabitedChildren.count >= 2, let stack = root.children.last else { return last }
    let stackOrientation = root.orientation.opposite
    if let stack = stack as? TilingContainer,
       stack.lifeStatus == .alive && stack.layout == .tiles && stack.orientation == stackOrientation
    {
        return BindingData(parent: stack, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }
    let stackBinding = stack.unbindFromParent()
    let container = TilingContainer(
        parent: root,
        adaptiveWeight: stackBinding.adaptiveWeight,
        stackOrientation,
        .tiles,
        index: stackBinding.index,
    )
    stack.bind(to: container, adaptiveWeight: WEIGHT_AUTO, index: 0)
    return BindingData(parent: container, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
}

@MainActor
func runOnWindowDetected(ifConventional window: Window) async {
    switch window.windowParentCases {
        case .tilingContainer, .floatingWindowsContainer, .macosMinimizedWindowsContainer,
             .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer:
            let layout = global_layoutForNextDetectedWindow
            global_layoutForNextDetectedWindow = nil
            defer {
                if let layout {
                    await LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [layout]))
                        .run(.defaultEnv.withWindowId(window.windowId), .emptyStdin)
                }
            }
            if let layout {
                await LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [layout]))
                    .run(.defaultEnv.withWindowId(window.windowId), .emptyStdin)
            }
            _ = await onWindowDetected(.defaultEnv, CmdIoImpl.emptyStdinIgnoringOut, window)
        case .macosPopupWindowsContainer, nil:
            break
    }
}

@MainActor
func onWindowDetected(_ env: CmdEnv, _ io: CmdIo, _ window: Window) async -> Int32ExitCode {
    broadcastEvent(.windowDetected(
        windowId: window.windowId,
        workspace: window.nodeWorkspace?.name,
        appBundleId: window.app.rawAppBundleId,
        appName: window.app.name,
    ))
    var lastExitCode = Int32ExitCode.succ
    let titleCache = WindowTitleCache()
    for callback in config.windowRules + config.onWindowDetected where await callback.matches(window, titleCache: titleCache) {
        lastExitCode = await callback.run.run(env.withWindowId(window.windowId), io)
        if !callback.checkFurtherCallbacks {
            return lastExitCode
        }
    }
    return lastExitCode
}

/// Regexes from the config that turned out to be too slow. They are not evaluated anymore until the config is reloaded
@MainActor private var timedOutRegexes: Set<String> = []
let regexTimeoutMs = 250
/// Window titles are controlled by other apps and by web pages. Nobody needs to match megabytes of a title
let maxRegexInputLength = 2000

@MainActor func resetTimedOutRegexes() { timedOutRegexes = [] }

/// Window managers must not hang because of a regex. See ``String.contains(caseInsensitiveRegex:timeoutMs:)``
@MainActor
func containsWithTimeout(_ string: String, _ regex: CaseInsensitiveRegex) async -> Bool {
    if timedOutRegexes.contains(regex.origin) { return false }
    let input = string.count > maxRegexInputLength ? String(string.prefix(maxRegexInputLength)) : string
    if let result = await input.contains(caseInsensitiveRegex: regex, timeoutMs: regexTimeoutMs) {
        return result
    }
    timedOutRegexes.insert(regex.origin)
    eprint("The regex '\(regex.origin)' didn't finish in \(regexTimeoutMs)ms. It is ignored until the config is reloaded")
    return false
}

/// Fetches the title of the window at most once, no matter how many callbacks need it
@MainActor
final class WindowTitleCache {
    private var title: String?? = nil

    func get(_ window: Window) async -> String? {
        if let title { return title }
        let fetched = try? await window.getTitle(.nonCancellable)
        title = .some(fetched)
        return fetched
    }
}

extension WindowDetectedCallback {
    @MainActor
    func matches(_ window: Window, titleCache: WindowTitleCache = WindowTitleCache()) async -> Bool {
        switch self.matcher {
            case .legacy(let matcher):
                if let startupMatcher = matcher.duringHyprSpaceStartup, startupMatcher != isStartup {
                    return false
                }
                if let regex = matcher.appIdOrNameRegex,
                   !(await containsWithTimeout(window.app.rawAppBundleId ?? "", regex)),
                   !(await containsWithTimeout(window.app.name ?? "", regex))
                {
                    return false
                }
                if let appId = matcher.appId, appId != window.app.rawAppBundleId {
                    return false
                }
                if let regex = matcher.appNameRegexSubstring, !(await containsWithTimeout(window.app.name ?? "", regex)) {
                    return false
                }
                if let workspace = matcher.workspace, workspace != window.nodeWorkspace?.name {
                    return false
                }
                // The title is checked last, because fetching it is a slow request to the app
                if let regex = matcher.windowTitleRegexSubstring {
                    guard let title = await titleCache.get(window), await containsWithTimeout(title, regex) else { return false }
                }
                return true
            case .command(let command):
                return await command.run(.defaultEnv.withWindowId(window.windowId), .emptyStdin).exitCode.rawValue == 0
        }
    }
}
