import AppKit
import Common

struct ListMonitorsCommand: Command {
    let args: ListMonitorsCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        let focus = globalFocus
        var result = globalSortedMonitorInfos
        if let focused = args.focused {
            result = result.filter { (monitor) in (monitor.visibleWorkspace == focus.workspace) == focused }
        }
        if let mouse = args.mouse {
            let mouseWorkspace = mouseLocation.monitorApproximation.visibleWorkspace
            result = result.filter { (monitor) in (monitor.visibleWorkspace == mouseWorkspace) == mouse }
        }

        if args.outputOnlyCount { return .succ(io.out("\(result.count)")) }
        return result.map(HyprObj.monitor).printFormatted(io, args.format, json: args.json, isDefaultFormat: args._format.isEmpty)
    }
}
