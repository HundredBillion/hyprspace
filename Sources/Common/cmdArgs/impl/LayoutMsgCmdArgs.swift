public struct LayoutMsgCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .layoutmsg,
        help: layoutmsg_help_generated,
        flags: [:],
        posArgs: [newMandatoryPosArgParser(\.message, parseLayoutMsg, placeholder: "<message>")],
    )

    public var message: Lateinit<Message> = .uninitialized

    public enum Message: Equatable, Sendable {
        case swapwithmaster
        case focusmaster
        case mfactDelta(Double)
        case mfactExact(Double)
        case togglesplit
        case cyclenext, cycleprev
        case swapnext, swapprev
    }
}

private func parseLayoutMsg(input: PosArgParserInput) -> ParsedCliArgs<LayoutMsgCmdArgs.Message> {
    let rest = Array(input.args.toArray().dropFirst(input.index))
    let count = rest.count
    func noParams(_ message: LayoutMsgCmdArgs.Message) -> ParsedCliArgs<LayoutMsgCmdArgs.Message> {
        rest.count == 1 ? .succ(message, advanceBy: count) : .fail("\(rest[0]): unexpected arguments", advanceBy: count)
    }
    return switch rest[0] {
        case "swapwithmaster": noParams(.swapwithmaster)
        case "focusmaster": noParams(.focusmaster)
        case "togglesplit": noParams(.togglesplit)
        case "cyclenext": noParams(.cyclenext)
        case "cycleprev": noParams(.cycleprev)
        case "swapnext": noParams(.swapnext)
        case "swapprev": noParams(.swapprev)
        case "mfact":
            if rest.count == 3, rest[1] == "exact", let value = Double(rest[2]), value.isFinite, (0.0 ... 1.0).contains(value) {
                .succ(.mfactExact(value), advanceBy: count)
            } else if rest.count == 2, let delta = Double(rest[1].removePrefix("+")), delta.isFinite, abs(delta) <= 1 {
                .succ(.mfactDelta(delta), advanceBy: count)
            } else {
                .fail("mfact: expected (<delta>|exact <ratio>). <delta> must be between -1.0 and 1.0. <ratio> must be between 0.0 and 1.0", advanceBy: count)
            }
        default:
            .fail(
                "Unknown layout message '\(rest[0])'. " +
                    "Possible values: swapwithmaster|focusmaster|mfact|togglesplit|cyclenext|cycleprev|swapnext|swapprev",
                advanceBy: count,
            )
    }
}
