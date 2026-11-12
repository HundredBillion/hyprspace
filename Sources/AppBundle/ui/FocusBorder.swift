import AppKit
import Common

/// Hyprland-like border around the focused window.
///
/// The border is a transparent click-through window that is owned by HyprSpace and placed around the focused window
@MainActor
final class FocusBorder {
    static let shared = FocusBorder()
    private var panel: NSWindow? = nil
    private let shapeLayer = CAShapeLayer()
    private var borderedWindowId: OpaqueWindowId? = nil
    private var shownRect: Rect? = nil
    private var shownConfig: BorderConfig? = nil

    private init() {}

    /// - Parameter rect: the rect of the focused window in the top-left based coordinate system
    func show(_ windowId: OpaqueWindowId, _ rect: Rect) {
        let border = config.border
        let width = CGFloat(border.width)
        if isUnitTest || !border.enabled || width <= 0 || !(rect.width > 0) || !(rect.height > 0) ||
            !rect.topLeftX.isFinite || !rect.topLeftY.isFinite || !rect.width.isFinite || !rect.height.isFinite
        {
            hide()
            return
        }
        if borderedWindowId == windowId, shownConfig == border, shownRect?.isAlmostEqual(to: rect, tolerance: 0) == true {
            return // Nothing has changed since the last time
        }
        borderedWindowId = windowId
        shownRect = rect
        shownConfig = border
        let panel = panel ?? createPanel()
        self.panel = panel

        // The border is drawn outside of the window
        let frame = borderFrame(windowRect: rect, borderWidth: width, mainMonitorHeight: mainMonitorInfo.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true) // No implicit animations. The border must stick to the window
        panel.setFrame(frame, display: false)
        shapeLayer.frame = CGRect(origin: .zero, size: frame.size)
        let strokeRect = CGRect(origin: .zero, size: frame.size).insetBy(dx: width / 2, dy: width / 2)
        let radius = min(CGFloat(border.rounding) + width / 2, min(strokeRect.width, strokeRect.height) / 2)
        shapeLayer.path = unsafe CGPath(roundedRect: strokeRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        shapeLayer.lineWidth = width
        shapeLayer.fillColor = nil
        shapeLayer.strokeColor = CGColor(
            srgbRed: border.activeColor.red,
            green: border.activeColor.green,
            blue: border.activeColor.blue,
            alpha: border.activeColor.alpha,
        )
        CATransaction.commit()
        panel.orderFrontRegardless()
    }

    func hide() {
        if borderedWindowId == nil { return }
        borderedWindowId = nil
        shownRect = nil
        shownConfig = nil
        panel?.orderOut(nil)
    }

    /// Makes the border follow the window during window animations
    func windowDidAnimate(_ windowId: OpaqueWindowId, _ rect: Rect) {
        if borderedWindowId == windowId {
            show(windowId, rect)
        }
    }

    private func createPanel() -> NSWindow {
        let panel = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        let view = NSView()
        view.wantsLayer = true
        view.layer?.addSublayer(shapeLayer)
        panel.contentView = view
        return panel
    }
}

/// Converts the rect of a window (top-left based coordinates, Y axis points down) to the frame of the border
/// window in AppKit coordinates (bottom-left based, Y axis points up). The border is placed outside of the window
func borderFrame(windowRect: Rect, borderWidth: CGFloat, mainMonitorHeight: CGFloat) -> CGRect {
    CGRect(
        x: windowRect.topLeftX - borderWidth,
        y: mainMonitorHeight - (windowRect.topLeftY + windowRect.height) - borderWidth,
        width: windowRect.width + 2 * borderWidth,
        height: windowRect.height + 2 * borderWidth,
    )
}

/// Doesn't talk to other apps: it only uses the rects that the layout pass already knows
@MainActor
func refreshFocusBorder() {
    if isUnitTest { return }
    guard config.border.enabled, TrayMenuModel.shared.isEnabled,
          let window = globalFocus.windowOrNil, !window.isFullscreen, !window.isHiddenInCorner,
          window.nodeWorkspace?.isVisible == true,
          window.windowId != currentlyManipulatedWithMouseWindowId // The rect is stale while the user drags the window
    else {
        FocusBorder.shared.hide()
        return
    }
    let rect: Rect? = switch window.parent {
        // The window is on its way. The animation keeps moving the border
        case is TilingContainer: animatedRect(of: window.windowId) ?? window.lastAppliedLayoutPhysicalRect
        case is FloatingWindowsContainer: window.lastKnownFloatingRect
        default: nil // macOS native fullscreen, minimized windows, popups, windows of hidden apps
    }
    if let rect {
        FocusBorder.shared.show(window.windowId, rect)
    } else {
        FocusBorder.shared.hide()
    }
}
