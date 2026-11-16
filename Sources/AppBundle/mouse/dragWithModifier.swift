import AppKit
import Common

/// Hyprland's `bindm = SUPER, mouse:272, movewindow` and `bindm = SUPER, mouse:273, resizewindow`.
/// Hold the modifier and drag anywhere on a window: the left mouse button moves the window, the right one resizes it.
///
/// The mouse events are swallowed, so the app under the cursor doesn't see the click. The window is moved and
/// resized through the Accessibility API, and the regular "window is manipulated with the mouse" machinery
/// (see moveWithMouse.swift and resizeWithMouse.swift) takes it from there, as if the user dragged the title bar
struct MouseDragModifier: Equatable {
    /// CGEventFlags
    let flags: UInt64

    static let supportedModifiers: [(name: String, flag: CGEventFlags)] = [
        ("alt", .maskAlternate), ("ctrl", .maskControl), ("cmd", .maskCommand), ("shift", .maskShift),
    ]
    static let allModifiersMask: UInt64 = supportedModifiers.reduce(0) { $0 | $1.flag.rawValue }

    /// - Returns: `.some(nil)` for 'off', `nil` if the string can't be parsed
    static func parse(_ raw: String) -> MouseDragModifier?? {
        let str = raw.trim().lowercased()
        if str == "off" || str.isEmpty { return .some(nil) }
        var flags: UInt64 = 0
        for part in str.split(separator: "-", omittingEmptySubsequences: false) {
            guard let modifier = supportedModifiers.first(where: { $0.name == part }) else { return nil }
            flags |= modifier.flag.rawValue
        }
        return MouseDragModifier(flags: flags)
    }
}

private struct ModifierDrag {
    let window: Window
    let isResize: Bool
    let startMouse: CGPoint
    /// Unknown until the app answers
    var start: (rect: Rect, resizesLeftEdge: Bool, resizesTopEdge: Bool)? = nil
}

@MainActor private var eventTap: CFMachPort? = nil
@MainActor private var eventTapSource: CFRunLoopSource? = nil
@MainActor private var activeModifier: MouseDragModifier? = nil
@MainActor private var drag: ModifierDrag? = nil

/// The window that is being dragged with the modifier. See ``isManipulatedWithMouse``
@MainActor var modifierDragWindowId: OpaqueWindowId? { drag?.window.windowId }

@MainActor func syncMouseDragModifier(_ config: Config) {
    activeModifier = config.mouseDragModifier
    if (activeModifier != nil) == (eventTap != nil) { return }
    if activeModifier == nil {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let eventTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes) }
        eventTap = nil
        eventTapSource = nil
        endModifierDrag()
        return
    }
    let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseDragged, .rightMouseUp]
    let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
    let tap = unsafe CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: modifierDragTapCallback,
        userInfo: nil,
    )
    guard let tap else {
        eprint("Can't create the event tap for 'mouse-drag-modifier'. Is the Accessibility permission granted?")
        return
    }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    // The source is added to the main run loop, that's why the callback is called on the main thread
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    eventTap = tap
    eventTapSource = source
}

private func modifierDragTapCallback(
    _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    _: UnsafeMutableRawPointer?,
) -> Unmanaged<CGEvent>? {
    let location = event.location
    let flags = event.flags.rawValue
    let isSwallowed = MainActor.assumeIsolated { handleModifierDragEvent(type, location: location, flags: flags) }
    return isSwallowed ? nil : unsafe Unmanaged.passUnretained(event)
}

/// - Returns: true if the event must not reach the app under the cursor
@MainActor
private func handleModifierDragEvent(_ type: CGEventType, location: CGPoint, flags: UInt64) -> Bool {
    switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables taps that are too slow. A drag that is in progress has lost its mouse up
            endModifierDrag()
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return false
        case .leftMouseDown, .rightMouseDown:
            if drag != nil { return true } // The other mouse button is pressed in the middle of the drag
            guard let activeModifier, flags & MouseDragModifier.allModifiersMask == activeModifier.flags,
                  TrayMenuModel.shared.isEnabled,
                  let window = managedWindow(at: location)
            else { return false }
            beginModifierDrag(window, isResize: type == .rightMouseDown, at: location)
            return true
        case .leftMouseDragged, .rightMouseDragged:
            guard let drag, drag.isResize == (type == .rightMouseDragged) else { return drag != nil }
            continueModifierDrag(drag, to: location)
            return true
        case .leftMouseUp, .rightMouseUp:
            guard let drag else { return false }
            if drag.isResize == (type == .rightMouseUp) { endModifierDrag() }
            return true
        default:
            return false
    }
}

/// Doesn't talk to other apps: the callback of the event tap must be fast
@MainActor
private func managedWindow(at location: CGPoint) -> Window? {
    let workspace = location.monitorApproximation.visibleWorkspace
    let floating = workspace.floatingWindowsContainer._mruChildren.lazy
        .compactMap { $0 as? Window }
        .first { $0.lastKnownFloatingRect?.contains(location) == true }
    let window = floating ?? location.findWindowRecursively(in: workspace.rootTilingContainer, virtual: false, fullscreenCoversAll: true)
    return window?.isFullscreen == true ? nil : window
}

@MainActor
private func beginModifierDrag(_ window: Window, isResize: Bool, at location: CGPoint) {
    drag = ModifierDrag(window: window, isResize: isResize, startMouse: location)
    Task.startUnstructured { @MainActor in
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        try await runLightSession(.focusFollowsMouse, token) {
            _ = window.focusWindow()
            window.nativeFocus()
        }
        guard let rect = try await window.getAxRect(.cancellable), drag?.window == window else { return }
        // Like in Hyprland, the corner that is the closest to the cursor is the one that is dragged
        drag?.start = (rect, location.x < rect.center.x, location.y < rect.center.y)
    }
}

@MainActor
private func continueModifierDrag(_ drag: ModifierDrag, to location: CGPoint) {
    guard let start = drag.start else { return } // The app hasn't answered yet
    let dx = location.x - drag.startMouse.x
    let dy = location.y - drag.startMouse.y
    let rect = drag.isResize
        ? resizedRect(start.rect, dx: dx, dy: dy, resizesLeftEdge: start.resizesLeftEdge, resizesTopEdge: start.resizesTopEdge)
        : Rect(topLeftX: start.rect.topLeftX + dx, topLeftY: start.rect.topLeftY + dy, width: start.rect.width, height: start.rect.height)
    // The AX notifications that follow are handled by movedObs and resizedObs
    drag.window.setAxFrame(rect.topLeftCorner, drag.isResize ? rect.size : nil)
}

@MainActor
private func endModifierDrag() {
    if drag == nil { return }
    drag = nil
    Task.startUnstructured { @MainActor in
        try await resetManipulatedWithMouseIfPossible()
        scheduleCancellableCompleteRefreshSession(.resetManipulatedWithMouse)
    }
}

/// The rect of the window after the corner that is the closest to the cursor was dragged by (dx, dy)
func resizedRect(_ rect: Rect, dx: CGFloat, dy: CGFloat, resizesLeftEdge: Bool, resizesTopEdge: Bool) -> Rect {
    // The opposite edges stay where they are, even when the window hits its minimal size
    let width = max(rect.width + (resizesLeftEdge ? -dx : dx), minFloatingWindowSide)
    let height = max(rect.height + (resizesTopEdge ? -dy : dy), minFloatingWindowSide)
    return Rect(
        topLeftX: resizesLeftEdge ? rect.maxX - width : rect.topLeftX,
        topLeftY: resizesTopEdge ? rect.maxY - height : rect.topLeftY,
        width: width,
        height: height,
    )
}
