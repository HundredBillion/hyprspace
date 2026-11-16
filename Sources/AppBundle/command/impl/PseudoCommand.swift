import AppKit
import Common

/// Hyprland's 'pseudo' dispatcher. A pseudotiled window keeps its own size inside of its tile
struct PseudoCommand: Command {
    let args: PseudoCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
        let newState: Bool = switch args.toggle {
            case .on: true
            case .off: false
            case .toggle: window.pseudotiledSize == nil
        }
        if !newState {
            window.pseudotiledSize = nil
            return .succ
        }
        if window.pseudotiledSize != nil { return .succ }
        // The size the window had the last time it was floating is its "own" size. Half of the tile is the fallback
        let ownSize: CGSize? = if let size = window.lastFloatingSize {
            size
        } else if let size = try? await window.getAxSize(.nonCancellable) {
            window.isFloating ? size : CGSize(width: size.width / 2, height: size.height / 2)
        } else {
            nil
        }
        guard let ownSize else { return .fail(io.err("Can't get the size of the window")) }
        window.pseudotiledSize = ownSize
        return .succ
    }
}
