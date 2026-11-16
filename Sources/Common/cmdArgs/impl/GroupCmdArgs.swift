public struct GroupCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .group,
        help: group_help_generated,
        flags: [
            "--window-id": windowIdSubArgParser(),
        ],
        posArgs: [newMandatoryPosArgParser(\.action, parseGroupAction, placeholder: "(toggle|next|prev|move-in <direction>|move-out)")],
    )

    public var action: Lateinit<Action> = .uninitialized

    public enum Action: Equatable, Sendable {
        case toggle
        case next, prev
        case moveIn(CardinalDirection)
        case moveOut
    }
}

private func parseGroupAction(input: PosArgParserInput) -> ParsedCliArgs<GroupCmdArgs.Action> {
    let rest = Array(input.args.toArray().dropFirst(input.index))
    let count = rest.count
    func noParams(_ action: GroupCmdArgs.Action) -> ParsedCliArgs<GroupCmdArgs.Action> {
        rest.count == 1 ? .succ(action, advanceBy: count) : .fail("\(rest[0]): unexpected arguments", advanceBy: count)
    }
    return switch rest[0] {
        case "toggle": noParams(.toggle)
        case "next": noParams(.next)
        case "prev": noParams(.prev)
        case "move-out": noParams(.moveOut)
        case "move-in":
            if rest.count == 2, let direction = CardinalDirection(rawValue: rest[1]) {
                .succ(.moveIn(direction), advanceBy: count)
            } else {
                .fail("move-in: expected exactly one argument: \(CardinalDirection.unionLiteral)", advanceBy: count)
            }
        default:
            .fail("Unknown group action '\(rest[0])'. Possible values: toggle|next|prev|move-in|move-out", advanceBy: count)
    }
}
