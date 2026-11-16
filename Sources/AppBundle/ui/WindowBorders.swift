import AppKit
import Common

/// Hyprland-like borders around windows.
///
/// A border is a transparent click-through window that is owned by HyprSpace. It is placed around the window it
/// belongs to, and right above that window in the z-order. That's how borders get covered by the same windows
/// that cover their window
@MainActor
final class WindowBorders {
    static let shared = WindowBorders()
    private var panels: [OpaqueWindowId: BorderPanel] = [:]

    private init() {}

    /// Shows the borders of the given windows and removes the borders of all the other windows
    func sync(_ borders: [WindowBorder]) {
        if isUnitTest { return }
        let wanted = borders.map(\.windowId).toSet()
        for (windowId, panel) in panels where !wanted.contains(windowId) {
            panel.close()
            panels.removeValue(forKey: windowId)
        }
        for border in borders {
            let panel = panels[border.windowId] ?? BorderPanel()
            panels[border.windowId] = panel
            panel.show(border)
        }
    }

    /// Makes the border follow the window during window animations
    func windowDidAnimate(_ windowId: OpaqueWindowId, _ rect: Rect) {
        panels[windowId]?.move(to: rect)
    }
}

struct WindowBorder: Equatable {
    let windowId: OpaqueWindowId
    /// The z-order of the border follows this window. nil if the window of macOS is unknown
    let nativeWindowId: UInt32?
    /// The rect of the window in the top-left based coordinate system
    var rect: Rect
    let style: BorderStyle
    /// The focused window is the one that changes its z-order. Its border is reordered on every sync
    let isFocused: Bool

    static func == (lhs: WindowBorder, rhs: WindowBorder) -> Bool {
        lhs.windowId == rhs.windowId && lhs.nativeWindowId == rhs.nativeWindowId && lhs.style == rhs.style &&
            lhs.isFocused == rhs.isFocused && lhs.rect.isAlmostEqual(to: rhs.rect, tolerance: 0)
    }
}

struct BorderStyle: Equatable {
    let color: BorderColor
    let width: Int
    let rounding: Int
}

@MainActor
private final class BorderPanel {
    private let panel: NSWindow
    private let gradientLayer = CAGradientLayer()
    private let shapeLayer = CAShapeLayer()
    private var shown: WindowBorder? = nil

    init() {
        panel = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        let view = NSView()
        view.wantsLayer = true
        // The gradient is only visible where the stroke of the shape is
        shapeLayer.fillColor = nil
        shapeLayer.strokeColor = .black
        gradientLayer.mask = shapeLayer
        view.layer?.addSublayer(gradientLayer)
        panel.contentView = view
    }

    func show(_ border: WindowBorder) {
        let isInvalid = border.style.width <= 0 || !(border.rect.width > 0) || !(border.rect.height > 0) ||
            !border.rect.topLeftX.isFinite || !border.rect.topLeftY.isFinite || !border.rect.width.isFinite || !border.rect.height.isFinite
        if isInvalid {
            panel.orderOut(nil)
            shown = nil
            return
        }
        if shown == border && !border.isFocused { return } // Nothing has changed since the last time
        if shown?.style != border.style || shown.map({ $0.rect.isAlmostEqual(to: border.rect, tolerance: 0) }) != true {
            applyGeometry(border.rect, border.style)
        }
        if let nativeWindowId = border.nativeWindowId {
            panel.level = .normal
            panel.order(.above, relativeTo: Int(nativeWindowId))
        } else {
            panel.level = .floating
            panel.orderFrontRegardless()
        }
        shown = border
    }

    func move(to rect: Rect) {
        guard var border = shown, !border.rect.isAlmostEqual(to: rect, tolerance: 0), rect.width > 0, rect.height > 0 else { return }
        border.rect = rect
        applyGeometry(rect, border.style)
        shown = border
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }

    private func applyGeometry(_ rect: Rect, _ style: BorderStyle) {
        let width = CGFloat(style.width)
        // The border is drawn outside of the window
        let frame = borderFrame(windowRect: rect, borderWidth: width, mainMonitorHeight: mainMonitorInfo.height)
        let bounds = CGRect(origin: .zero, size: frame.size)
        CATransaction.begin()
        CATransaction.setDisableActions(true) // No implicit animations. The border must stick to the window
        panel.setFrame(frame, display: false)
        gradientLayer.frame = bounds
        shapeLayer.frame = bounds
        let strokeRect = bounds.insetBy(dx: width / 2, dy: width / 2)
        let radius = min(CGFloat(style.rounding) + width / 2, min(strokeRect.width, strokeRect.height) / 2)
        shapeLayer.path = unsafe CGPath(roundedRect: strokeRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        shapeLayer.lineWidth = width
        let colors = style.color.colors.map { CGColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha) }
        // CAGradientLayer needs at least two colors
        gradientLayer.colors = colors.count == 1 ? [colors[0], colors[0]] : colors
        let (start, end) = gradientPoints(angleDegrees: style.color.angleDegrees)
        gradientLayer.startPoint = start
        gradientLayer.endPoint = end
        CATransaction.commit()
    }
}

/// The start and the end of the gradient in the unit coordinate space of a layer (Y axis points up).
/// 0deg goes from left to right. 90deg goes from top to bottom
func gradientPoints(angleDegrees: Double) -> (start: CGPoint, end: CGPoint) {
    let radians = angleDegrees * .pi / 180
    let dx = cos(radians) / 2
    let dy = -sin(radians) / 2
    return (CGPoint(x: 0.5 - dx, y: 0.5 - dy), CGPoint(x: 0.5 + dx, y: 0.5 + dy))
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

/// Apps are free to ignore the frame that the layout asks for: a window has a minimal size, a terminal snaps its
/// size to the size of a character. The border must go around the window as it is, not around its tile.
/// The value is the real frame of a tiling window whose tile is `layout`
@MainActor private var realFrames: [OpaqueWindowId: (layout: Rect, real: Rect)] = [:]
@MainActor private var reconcileBordersTask: Task<(), any Error>? = nil

/// The frames of the windows on the screen as the window server knows them, by the window ID of macOS.
/// The coordinate system is the same as in `Rect`. Doesn't talk to other apps
func onScreenWindowFrames() -> [UInt32: Rect] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [:] }
    var result: [UInt32: Rect] = [:]
    for window in windows {
        guard let number = window[kCGWindowNumber as String] as? UInt32,
              let bounds = window[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds)
        else { continue }
        result[number] = Rect(topLeftX: frame.minX, topLeftY: frame.minY, width: frame.width, height: frame.height)
    }
    return result
}

/// Doesn't talk to other apps: it only uses the rects that the layout pass already knows
@MainActor
func refreshWindowBorders() {
    syncWindowBorders()
    if isUnitTest || !config.border.enabled { return }
    // The apps need time to apply the frames of the layout (and the animation needs time to finish).
    // Then the borders are compared against the real frames of the windows
    reconcileBordersTask?.cancel()
    reconcileBordersTask = Task.startUnstructured { @MainActor in
        try await Task.sleep(for: .milliseconds(min(max(config.animations.durationMs, 0), maxAnimationDurationMs) + 150))
        if updateRealFrames(onScreenWindowFrames()) { syncWindowBorders() }
    }
}

/// - Returns: true if the real frame of some window has changed
@MainActor
private func updateRealFrames(_ onScreen: [UInt32: Rect]) -> Bool {
    var updated: [OpaqueWindowId: (layout: Rect, real: Rect)] = [:]
    for workspace in Workspace.all where workspace.isVisible {
        for window in workspace.allLeafWindowsRecursive where window.parent is TilingContainer {
            guard animatedRect(of: window.windowId) == nil, // The window is still on its way
                  let layout = window.lastAppliedLayoutPhysicalRect,
                  let nativeWindowId = (window as? MacWindow).flatMap({ $0.macApp.nativeWindowId(of: $0.windowId) }),
                  let real = onScreen[nativeWindowId],
                  isFrameMismatch(layout: layout, real: real)
            else { continue }
            updated[window.windowId] = (layout, real)
        }
    }
    let isChanged = updated.count != realFrames.count || updated.contains { id, value in
        realFrames[id].map { $0.layout.isAlmostEqual(to: value.layout, tolerance: 0) && $0.real.isAlmostEqual(to: value.real, tolerance: 0) } != true
    }
    realFrames = updated
    return isChanged
}

/// The window didn't take the frame of its tile. A pixel of difference is not worth a different border
func isFrameMismatch(layout: Rect, real: Rect) -> Bool { !real.isAlmostEqual(to: layout, tolerance: 1) }

@MainActor
private func syncWindowBorders() {
    if isUnitTest { return }
    guard config.border.enabled, TrayMenuModel.shared.isEnabled else {
        WindowBorders.shared.sync([])
        return
    }
    let focused = globalFocus.windowOrNil
    var borders: [WindowBorder] = []
    for workspace in Workspace.all where workspace.isVisible {
        for window in workspace.allLeafWindowsRecursive {
            let isFocused = window == focused
            guard let color = isFocused ? config.border.activeColor : config.border.inactiveColor,
                  let rect = borderRect(of: window)
            else { continue }
            borders.append(WindowBorder(
                windowId: window.windowId,
                nativeWindowId: (window as? MacWindow).flatMap { $0.macApp.nativeWindowId(of: $0.windowId) },
                rect: rect,
                style: BorderStyle(color: color, width: config.border.width, rounding: config.border.rounding),
                isFocused: isFocused,
            ))
        }
    }
    WindowBorders.shared.sync(borders)
}

/// - Returns: nil if the window must not have a border right now
@MainActor
private func borderRect(of window: Window) -> Rect? {
    if window.isFullscreen || window.isHiddenInCorner { return nil }
    if window.windowId == currentlyManipulatedWithMouseWindowId { return nil } // The rect is stale while the user drags the window
    return switch window.parent {
        case is TilingContainer:
            // The window is on its way. The animation keeps moving the border
            if let animated = animatedRect(of: window.windowId) {
                animated
            } else if let layout = window.lastAppliedLayoutPhysicalRect, let known = realFrames[window.windowId],
                      known.layout.isAlmostEqual(to: layout, tolerance: 0)
            {
                known.real // The window didn't take the frame of its tile
            } else {
                window.lastAppliedLayoutPhysicalRect
            }
        case is FloatingWindowsContainer: window.lastKnownFloatingRect
        default: nil // macOS native fullscreen, minimized windows, popups, windows of hidden apps
    }
}
