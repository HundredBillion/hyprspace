public struct ResizeActiveCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .resizeactive,
        help: resizeactive_help_generated,
        flags: [:],
        posArgs: [newMandatoryPosArgParser(\.params, parseResizeActiveParams, placeholder: "[exact] <x> <y>")],
    )

    public var params: Lateinit<Params> = .uninitialized

    public struct Params: Equatable, Sendable {
        public let exact: Bool
        public let x: Int
        public let y: Int

        public init(exact: Bool, x: Int, y: Int) {
            self.exact = exact
            self.x = x
            self.y = y
        }
    }
}

private let resizeActiveMaxPixels = 100_000

private func parseResizeActiveParams(input: PosArgParserInput) -> ParsedCliArgs<ResizeActiveCmdArgs.Params> {
    var rest = Array(input.args.toArray().dropFirst(input.index))
    let count = rest.count
    let exact = rest.first == "exact"
    if exact { rest.removeFirst() }
    guard rest.count == 2, let x = Int(rest[0].removePrefix("+")), let y = Int(rest[1].removePrefix("+")) else {
        return .fail("Expected arguments: [exact] <x> <y>. <x> and <y> must be integers", advanceBy: count)
    }
    let range = -resizeActiveMaxPixels ... resizeActiveMaxPixels
    if !range.contains(x) || !range.contains(y) {
        return .fail("<x> and <y> must be between -\(resizeActiveMaxPixels) and \(resizeActiveMaxPixels)", advanceBy: count)
    }
    if exact && (x < 0 || y < 0) {
        return .fail("'exact' sizes can't be negative", advanceBy: count)
    }
    return .succ(.init(exact: exact, x: x, y: y), advanceBy: count)
}
