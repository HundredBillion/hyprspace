import AppKit
import Common

struct PinCommand: Command {
    let args: PinCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
        guard window.isFloating else {
            return .fail(io.err("Only floating windows can be pinned. Tip: use 'layout floating' first"))
        }
        window.isPinned.toggle()
        return .succ
    }
}

/// Pinned floating windows follow the visible workspace of their monitor
@MainActor
func movePinnedWindows(from oldWorkspace: Workspace, to newWorkspace: Workspace) {
    if oldWorkspace == newWorkspace { return }
    let pinned = oldWorkspace.floatingWindowsContainer.children.filterIsInstance(of: Window.self).filter(\.isPinned)
    if pinned.isEmpty { return }
    let mru = newWorkspace.mostRecentWindowRecursive
    for window in pinned {
        window.bindAsFloatingWindow(to: newWorkspace)
    }
    mru?.markAsMostRecentChild() // Pinned windows must not steal the focus on the new workspace
}
