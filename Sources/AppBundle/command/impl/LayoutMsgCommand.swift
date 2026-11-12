import AppKit
import Common

struct LayoutMsgCommand: Command {
    let args: LayoutMsgCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        let root = target.workspace.rootTilingContainer
        switch args.message.val {
            case .swapwithmaster:
                guard let window = target.windowOrNil, !window.isFloating else {
                    return .fail(io.err("swapwithmaster: no tiling window is focused"))
                }
                guard let master = root.masterWindow else { return .fail }
                // If the master itself is focused, it is swapped with the first window of the stack
                let other = window == master ? root.firstStackWindow : master
                guard let other else { return .fail(io.err("swapwithmaster: there is only one window")) }
                swapWindows(mruDominant: window, other)
                return .from(bool: window.focusWindow())
            case .focusmaster:
                guard let master = root.masterWindow else { return .fail }
                return .from(bool: master.focusWindow())
            case .mfactDelta(let delta):
                return setMasterFactor(root, io) { $0 + delta }
            case .mfactExact(let ratio):
                return setMasterFactor(root, io) { _ in ratio }
            case .togglesplit: return await runNativeCommand(["layout", "horizontal", "vertical"], env)
            case .cyclenext: return await runNativeCommand(["focus", "--boundaries-action", "wrap-around-the-workspace", "dfs-next"], env)
            case .cycleprev: return await runNativeCommand(["focus", "--boundaries-action", "wrap-around-the-workspace", "dfs-prev"], env)
            case .swapnext: return await runNativeCommand(["swap", "--wrap-around", "dfs-next"], env)
            case .swapprev: return await runNativeCommand(["swap", "--wrap-around", "dfs-prev"], env)
        }
    }
}

@MainActor
private func runNativeCommand(_ args: [String], _ env: CmdEnv) async -> BinaryExitCode {
    switch parseCommand(args) {
        case .cmd(let command): .from(bool: await command.run(env, .emptyStdin).exitCode.rawValue == EXIT_CODE_ZERO)
        case .failure, .help: .fail
    }
}

/// The master is the first child of the root container. Everything else is the stack
@MainActor
private func setMasterFactor(_ root: TilingContainer, _ io: CmdIo, _ transform: (Double) -> Double) -> BinaryExitCode {
    let children = root.inhabitedChildren
    guard root.layout == .tiles, children.count >= 2, let master = children.first else {
        return .fail(io.err("mfact: the workspace must have a master and a stack"))
    }
    let orientation = root.orientation
    let total = children.sumOfDouble { $0.getWeight(orientation) }
    let stackTotal = total - master.getWeight(orientation)
    if !(total > 0) || !(stackTotal > 0) { return .fail }
    let ratio = min(max(transform(Double(master.getWeight(orientation) / total)), 0.05), 0.95)
    if !ratio.isFinite || !total.isFinite || !stackTotal.isFinite { return .fail }
    let newStackTotal = total * (1 - ratio)
    for child in children.dropFirst() {
        child.setWeight(orientation, child.getWeight(orientation) / stackTotal * newStackTotal)
    }
    master.setWeight(orientation, total * ratio)
    return .succ
}

extension TilingContainer {
    @MainActor fileprivate var masterWindow: Window? {
        inhabitedChildren.first?.allLeafWindowsRecursive.first { $0.lifeStatus.isInhabited }
    }

    @MainActor fileprivate var firstStackWindow: Window? {
        inhabitedChildren.dropFirst().lazy.compactMap { $0.allLeafWindowsRecursive.first { $0.lifeStatus.isInhabited } }.first
    }
}
