import AppKit
import Common

@MainActor var currentlyManipulatedWithMouseWindowId: OpaqueWindowId? = nil
var isLeftMouseButtonDown: Bool { NSEvent.pressedMouseButtons == 1 }

@MainActor
func isManipulatedWithMouse(_ window: Window) async throws -> Bool {
    // The mouse events of the modifier drag are swallowed, and the window doesn't have to be focused yet
    if window.windowId == modifierDragWindowId { return !window.isHiddenInCorner }
    return try await (!window.isHiddenInCorner && // Don't allow to resize/move windows of hidden workspaces
        isLeftMouseButtonDown &&
        (currentlyManipulatedWithMouseWindowId == nil || window.windowId == currentlyManipulatedWithMouseWindowId))
        .andAsync { @Sendable @MainActor in try await getNativeFocusedWindow(.cancellable) == window }
}

enum MouseManipulationKind { case move, resize }

/// A newer notification of the same kind supersedes the session that is still in progress
@MainActor private var manipulatedWithMouseTasks: [MouseManipulationKind: Task<(), any Error>] = [:]

/// The common part of the AX observers that are called when a window is moved or resized.
/// - Parameter body: called if it's the user who moves or resizes the window with the mouse
func manipulatedWithMouseObs(
    _ kind: MouseManipulationKind,
    ax: AXUIElement,
    notif: CFString,
    body: @escaping @MainActor (Window) async throws -> (),
) {
    let nativeWindowId = ax.containingNativeWindowId()
    let notif = notif as String
    let pid = ax.pid
    Task.startUnstructured { @MainActor in
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        let window: Window? = if let nativeWindowId, let pid { Window.get(byNativeId: nativeWindowId, pid: pid) } else { nil }
        // The window animation moves and resizes windows many times in a row. Those notifications are our own echo.
        // The notification that follows the last animation step still triggers the refresh
        if let window, animatedRect(of: window.windowId) != nil { return }
        guard let window, try await isManipulatedWithMouse(window) else {
            scheduleCancellableCompleteRefreshSession(.ax(notif))
            return
        }
        manipulatedWithMouseTasks[kind]?.cancel()
        manipulatedWithMouseTasks[kind] = Task.startUnstructured {
            try checkCancellation()
            try await runLightSession(.ax(notif), token) {
                try await body(window)
            }
        }
    }
}

/// Same motivation as in monitorFrameNormalized
var mouseLocation: CGPoint { NSEvent.mouseLocation.withYAxisFlipped }
