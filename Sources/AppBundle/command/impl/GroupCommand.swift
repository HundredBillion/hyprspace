import AppKit
import Common

/// Hyprland-like window groups. A group is a tiling container with the accordion layout: its windows share one tile
struct GroupCommand: Command {
    let args: GroupCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
        guard let parent = window.parent as? TilingContainer else { return .fail(io.err("The window is non-tiling")) }
        switch args.action.val {
            case .toggle:
                // Like in i3, the window is grouped with the windows it shares the container with
                parent.layout = parent.layout == .accordion ? .tiles : .accordion
                return .succ
            case .next, .prev:
                guard parent.layout == .accordion else { return .fail(io.err(notInGroup)) }
                let siblings = parent.inhabitedChildren
                guard let index = siblings.firstIndex(of: window) else { return .fail(io.err(bugPrompt())) }
                let offset = args.action.val == .next ? 1 : -1
                let neighbor = siblings[(index + offset + siblings.count) % siblings.count]
                guard let windowToFocus = neighbor as? Window ?? neighbor.mostRecentWindowRecursive else { return .fail }
                return .from(bool: windowToFocus.focusWindow())
            case .moveOut:
                guard parent.layout == .accordion else { return .fail(io.err(notInGroup)) }
                guard let grandParent = parent.parent as? TilingContainer, let groupIndex = parent.ownIndex(in: .all) else {
                    return .fail(io.err("The group takes the whole workspace. Tip: use 'group toggle' to dissolve it"))
                }
                window.unbindFromParent()
                window.bind(to: grandParent, adaptiveWeight: WEIGHT_AUTO, index: groupIndex + 1)
                return .from(bool: window.focusWindow())
            case .moveIn(let direction):
                guard let (neighborParent, _, neighborIndex) = window.closestParent(hasInhabitedChildrenInDirection: direction, withLayout: nil),
                      let neighbor = neighborParent.children[neighborIndex].findInhabitedLeafWindowRecursive(snappedTo: direction.opposite)
                else {
                    return .fail(io.err("No windows in the specified direction"))
                }
                if let group = neighbor.parent as? TilingContainer, group.layout == .accordion {
                    if group == parent { return .fail(io.err("The windows are already in the same group")) }
                    window.unbindFromParent()
                    window.bind(to: group, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
                } else {
                    // There is no group in that direction yet. The neighbor and the window become a new group
                    let neighborBinding = neighbor.unbindFromParent()
                    let group = TilingContainer(
                        parent: neighborBinding.parent,
                        adaptiveWeight: neighborBinding.adaptiveWeight,
                        (neighborBinding.parent as? TilingContainer)?.orientation.opposite ?? .h,
                        .accordion,
                        index: neighborBinding.index,
                    )
                    window.unbindFromParent()
                    neighbor.bind(to: group, adaptiveWeight: WEIGHT_AUTO, index: 0)
                    window.bind(to: group, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
                }
                return .from(bool: window.focusWindow())
        }
    }
}

private let notInGroup = "The window is not in a group. Tip: use 'group toggle' or 'group move-in <direction>' first"
