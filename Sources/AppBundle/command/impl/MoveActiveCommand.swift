import AppKit
import Common

/// Hyprland's 'moveactive' dispatcher
struct MoveActiveCommand: Command {
    let args: MoveActiveCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        let params = args.params.val
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
        guard window.isFloating else {
            return .fail(io.err("Only floating windows can be moved freely. Tip: use 'layout floating' first"))
        }
        guard let rect = try? await window.getAxRect(.nonCancellable) else { return .fail(io.err("Can't get the position of the window")) }
        let monitor = rect.center.monitorApproximation.visibleRect
        let topLeft: CGPoint = params.exact
            // 'exact' coordinates are relative to the monitor of the window
            ? CGPoint(
                x: monitor.topLeftX + (params.xIsPercent ? monitor.width * CGFloat(params.x) / 100 : CGFloat(params.x)),
                y: monitor.topLeftY + (params.yIsPercent ? monitor.height * CGFloat(params.y) / 100 : CGFloat(params.y)),
            )
            : CGPoint(x: rect.topLeftX + CGFloat(params.x), y: rect.topLeftY + CGFloat(params.y))
        window.setAxFrame(topLeft, nil)
        return .succ
    }
}

/// Hyprland's 'centerwindow' dispatcher
struct CenterWindowCommand: Command {
    let args: CenterWindowCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
        guard window.isFloating else {
            return .fail(io.err("Only floating windows can be centered. Tip: use 'layout floating' first"))
        }
        guard let rect = try? await window.getAxRect(.nonCancellable) else { return .fail(io.err("Can't get the position of the window")) }
        let monitor = (window.nodeMonitorInfo ?? rect.center.monitorApproximation).visibleRect
        window.setAxFrame(centeredRect(of: rect.size, in: monitor).topLeftCorner, nil)
        return .succ
    }
}

func centeredRect(of size: CGSize, in container: Rect) -> Rect {
    Rect(
        topLeftX: container.topLeftX + (container.width - size.width) / 2,
        topLeftY: container.topLeftY + (container.height - size.height) / 2,
        width: size.width,
        height: size.height,
    )
}
