import AppKit
import Common

struct ResizeActiveCommand: Command {
    let args: ResizeActiveCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        let params = args.params.val
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
            let resize = ResizeCommand(args: ResizeCmdArgs(rawArgs: [], dimension: dimension, units: units))
            if resize.run(env, io).rawValue != EXIT_CODE_ZERO { result = .fail }
        }
        return result
    }
}
