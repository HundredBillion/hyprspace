import AppKit
import Common

/// Hyprland-like window animations.
///
/// macOS doesn't allow third party apps to animate windows of other apps in the compositor,
/// so the animation is emulated by resizing the window several times in a row through the Accessibility API
private struct WindowAnimation {
    let id: Int
    let target: Rect
    var current: Rect
    let task: Task<(), Never>
}

@MainActor private var windowAnimations: [OpaqueWindowId: WindowAnimation] = [:]
@MainActor private var lastAnimationId = 0
/// Animations (by id) that have sent a frame to the app and the app hasn't processed it yet.
/// Apps that are slow to resize get fewer but complete steps, instead of a queue of half-applied ones
@MainActor private var animationsWithStepInFlight: Set<Int> = []
private let animationFps = 60

/// Apps that repeatedly failed to keep up with the animation. Their windows are not animated anymore: a window that
/// stutters through an animation feels worse than a window that jumps to its place
@MainActor private var slowAnimationStrikes: [pid_t: Int] = [:]
private let maxSlowAnimationStrikes = 3

@MainActor func resetSlowAnimationApps() { slowAnimationStrikes = [:] }

/// The animation is too slow if the app was still busy with the previous frame most of the time
func isAnimationTooSlow(sentFrames: Int, droppedFrames: Int) -> Bool {
    sentFrames + droppedFrames >= 4 && droppedFrames > sentFrames
}

/// The rect of the window in the middle of its animation. nil if the window isn't being animated
@MainActor
func animatedRect(of windowId: OpaqueWindowId) -> Rect? { windowAnimations[windowId]?.current }

@MainActor
func cancelWindowAnimation(_ windowId: OpaqueWindowId) {
    windowAnimations.removeValue(forKey: windowId)?.task.cancel()
}

extension Window {
    /// - Parameter old: the previous rect of the window as known by the layout engine. nil if the window is new
    @MainActor
    func setAxFrameAnimated(from old: Rect?, to target: Rect) {
        let animations = config.animations
        // Windows must follow the cursor without a delay while the user drags or resizes a window with the mouse
        let isAnimationAllowed = animations.enabled && !isUnitTest && currentlyManipulatedWithMouseWindowId == nil &&
            slowAnimationStrikes[app.pid, default: 0] < maxSlowAnimationStrikes
        if let running = windowAnimations[windowId] {
            if running.target.isAlmostEqual(to: target) { return } // The window is already on its way
            cancelWindowAnimation(windowId)
            if isAnimationAllowed {
                startAnimation(from: running.current, to: target, steps: animationSteps(animations))
                return
            }
        }
        let steps = animationSteps(animations)
        guard isAnimationAllowed, steps >= 2, let old, !old.isAlmostEqual(to: target) else {
            setAxFrame(target.topLeftCorner, target.size)
            return
        }
        startAnimation(from: old, to: target, steps: steps)
    }

    @MainActor
    private func startAnimation(from: Rect, to target: Rect, steps: Int) {
        let steps = max(1, steps)
        lastAnimationId += 1
        let id = lastAnimationId
        let windowId = windowId
        let pid = app.pid
        let task = Task { @MainActor [weak self] in
            defer {
                animationsWithStepInFlight.remove(id)
                if windowAnimations[windowId]?.id == id {
                    windowAnimations.removeValue(forKey: windowId)
                }
            }
            var lastSent = from
            var sentFrames = 0
            var droppedFrames = 0
            for step in 1 ... steps {
                guard let self, windowAnimations[windowId]?.id == id else { return }
                let isLast = step == steps
                let rect = isLast ? target : interpolate(from: from, to: target, progress: easeOutCubic(Double(step) / Double(steps)))
                if isLast {
                    // The last step always sets the full frame to make sure that the window ends up exactly at the target
                    self.setAxFrameForAnimationStep(rect.topLeftCorner, rect.size, isIntermediate: false) {}
                    if isAnimationTooSlow(sentFrames: sentFrames, droppedFrames: droppedFrames) {
                        slowAnimationStrikes[pid, default: 0] += 1
                    }
                } else if rect.isAlmostEqual(to: lastSent) {
                    // The easing curve produces identical frames at its tail. Nothing to send
                } else if animationsWithStepInFlight.contains(id) {
                    droppedFrames += 1 // The app is still busy with the previous step. Drop the frame
                } else {
                    sentFrames += 1
                    let isMoved = rect.topLeftX != lastSent.topLeftX || rect.topLeftY != lastSent.topLeftY
                    let isResized = rect.width != lastSent.width || rect.height != lastSent.height
                    animationsWithStepInFlight.insert(id)
                    self.setAxFrameForAnimationStep(isMoved ? rect.topLeftCorner : nil, isResized ? rect.size : nil, isIntermediate: true) {
                        Task { @MainActor in animationsWithStepInFlight.remove(id) }
                    }
                    lastSent = rect
                }
                windowAnimations[windowId]?.current = lastSent
                FocusBorder.shared.windowDidAnimate(windowId, rect)
                if !isLast {
                    do { try await Task.sleep(for: .milliseconds(1000 / animationFps)) } catch { return }
                }
            }
        }
        windowAnimations[windowId] = WindowAnimation(id: id, target: target, current: from, task: task)
    }
}

private func animationSteps(_ animations: AnimationsConfig) -> Int {
    min(max(animations.durationMs, 0), maxAnimationDurationMs) * animationFps / 1000
}

func easeOutCubic(_ progress: Double) -> Double {
    let p = min(max(progress, 0), 1)
    return 1 - pow(1 - p, 3)
}

func interpolate(from: Rect, to: Rect, progress: Double) -> Rect {
    let p = CGFloat(progress)
    func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { (a + (b - a) * p).rounded() }
    return Rect(
        topLeftX: lerp(from.topLeftX, to.topLeftX),
        topLeftY: lerp(from.topLeftY, to.topLeftY),
        width: lerp(from.width, to.width),
        height: lerp(from.height, to.height),
    )
}

extension Rect {
    func isAlmostEqual(to other: Rect, tolerance: CGFloat = 0.5) -> Bool {
        abs(topLeftX - other.topLeftX) <= tolerance && abs(topLeftY - other.topLeftY) <= tolerance &&
            abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
