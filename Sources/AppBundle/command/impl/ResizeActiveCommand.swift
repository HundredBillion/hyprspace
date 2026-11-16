import AppKit
import Common

struct ResizeActiveCommand: Command {
    let args: ResizeActiveCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        let params = args.params.val
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        if let window = target.windowOrNil, window.isFloating {
            return await resizeFloatingWindow(window, params, io)
        }
        if params.xIsPercent || params.yIsPercent {
            return .fail(io.err("Percentages are only supported for floating windows"))
        }
        var result: BinaryExitCode = .succ
        for (dimension, value) in [(ResizeCmdArgs.Dimension.width, params.x), (.height, params.y)] {
            let units: ResizeCmdArgs.Units
            switch true {
                case value == 0: continue // Zero means "don't change this dimension"
                case params.exact: units = .set(UInt(value))
                case value > 0: units = .add(UInt(value))
                case value < 0: units = .subtract(value.magnitude)
                default: continue
            }
            var resizeArgs = ResizeCmdArgs(rawArgs: [], dimension: dimension, units: units)
            resizeArgs.windowId = args.windowId
            if ResizeCommand(args: resizeArgs).run(env, io).rawValue != EXIT_CODE_ZERO { result = .fail }
        }
        return result
    }
}

@MainActor
private func resizeFloatingWindow(_ window: Window, _ params: ResizeActiveCmdArgs.Params, _ io: CmdIo) async -> BinaryExitCode {
    guard let rect = try? await window.getAxRect(.nonCancellable) else { return .fail(io.err("Can't get the size of the window")) }
    let monitor = rect.center.monitorApproximation.visibleRect
    var size = rect.size
    if params.exact {
        // Zero means "don't change this dimension"
        if params.x != 0 { size.width = params.xIsPercent ? monitor.width * CGFloat(params.x) / 100 : CGFloat(params.x) }
        if params.y != 0 { size.height = params.yIsPercent ? monitor.height * CGFloat(params.y) / 100 : CGFloat(params.y) }
    } else {
        size.width += CGFloat(params.x)
        size.height += CGFloat(params.y)
    }
    size = CGSize(width: max(size.width, minFloatingWindowSide), height: max(size.height, minFloatingWindowSide))
    window.lastFloatingSize = size
    window.setAxFrame(nil, size)
    return .succ
}

/// Windows can't be resized to nothing with the keyboard: it would be hard to get them back
let minFloatingWindowSide: CGFloat = 50
