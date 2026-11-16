import AppKit
import Common

struct SwapCommand: Command {
    let args: SwapCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache: Bool = true

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else {
            return .fail
        }

        guard let currentWindow = target.windowOrNil else {
            return .fail(io.err(noWindowIsFocused))
        }

        let targetWindow: Window?
        switch args.target.val {
            case .direction(let direction):
                switch currentWindow.closestParent(hasInhabitedChildrenInDirection: direction, withLayout: nil) {
                    case let (parent, _, neighborIndex)?:
                        targetWindow = parent.children[neighborIndex].findInhabitedLeafWindowRecursive(snappedTo: direction.opposite)
                    case nil where args.wrapAround:
                        targetWindow = target.workspace.findInhabitedLeafWindowRecursive(snappedTo: direction.opposite)
                    case nil:
                        return .fail
                }
            case .dfsNextPrev(let nextPrev):
                guard let neighbor = target.dfsNeighbor(nextPrev), !neighbor.isWrappedAround || args.wrapAround else {
                    return .fail
                }
                targetWindow = neighbor.window
        }

        guard let targetWindow else {
            return .fail
        }

        swapWindows(mruDominant: currentWindow, targetWindow)

        if args.swapFocus {
            return .from(bool: targetWindow.focusWindow())
        }
        return .succ
    }
}
