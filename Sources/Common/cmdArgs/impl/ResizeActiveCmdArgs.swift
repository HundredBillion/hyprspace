public struct ResizeActiveCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .resizeactive,
        help: resizeactive_help_generated,
        flags: [
            "--window-id": windowIdSubArgParser(),
        ],
        posArgs: [newMandatoryPosArgParser(\.params, parseResizeActiveParams, placeholder: "[exact] <x> <y>")],
    )

    public var params: Lateinit<Params> = .uninitialized

    /// The parameters of Hyprland's 'resizeactive' and 'moveactive' dispatchers: `[exact] <x> <y>`
    public struct Params: Equatable, Sendable {
        public let exact: Bool
        public let x: Int
        public let y: Int
        /// `<x>` is a percentage of the monitor width. Only possible together with `exact`
        public let xIsPercent: Bool
        /// `<y>` is a percentage of the monitor height. Only possible together with `exact`
        public let yIsPercent: Bool

        public init(exact: Bool, x: Int, y: Int, xIsPercent: Bool = false, yIsPercent: Bool = false) {
            self.exact = exact
            self.x = x
            self.y = y
            self.xIsPercent = xIsPercent
            self.yIsPercent = yIsPercent
        }
    }
}

public struct MoveActiveCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .moveactive,
        help: moveactive_help_generated,
        flags: [
            "--window-id": windowIdSubArgParser(),
        ],
        posArgs: [newMandatoryPosArgParser(\.params, parseMoveActiveParams, placeholder: "[exact] <x> <y>")],
    )

    public var params: Lateinit<ResizeActiveCmdArgs.Params> = .uninitialized
}

private let resizeActiveMaxPixels = 100_000

private func parseResizeActiveParams(input: PosArgParserInput) -> ParsedCliArgs<ResizeActiveCmdArgs.Params> {
    parseExactXY(input, allowNegativeExact: false)
}

private func parseMoveActiveParams(input: PosArgParserInput) -> ParsedCliArgs<ResizeActiveCmdArgs.Params> {
    parseExactXY(input, allowNegativeExact: true)
}

private func parseExactXY(_ input: PosArgParserInput, allowNegativeExact: Bool) -> ParsedCliArgs<ResizeActiveCmdArgs.Params> {
    var rest = Array(input.args.toArray().dropFirst(input.index))
    let count = rest.count
    let exact = rest.first == "exact"
    if exact { rest.removeFirst() }
    func parse(_ raw: String) -> (value: Int, isPercent: Bool)? {
        let isPercent = raw.hasSuffix("%")
        return Int((isPercent ? String(raw.dropLast()) : raw).removePrefix("+")).map { ($0, isPercent) }
    }
    guard rest.count == 2, let x = parse(rest[0]), let y = parse(rest[1]) else {
        return .fail("Expected arguments: [exact] <x> <y>. <x> and <y> must be integers", advanceBy: count)
    }
    let range = -resizeActiveMaxPixels ... resizeActiveMaxPixels
    if !range.contains(x.value) || !range.contains(y.value) {
        return .fail("<x> and <y> must be between -\(resizeActiveMaxPixels) and \(resizeActiveMaxPixels)", advanceBy: count)
    }
    if (x.isPercent || y.isPercent) && !exact {
        return .fail("Percentages are only allowed together with 'exact'", advanceBy: count)
    }
    if exact && !allowNegativeExact && (x.value < 0 || y.value < 0) {
        return .fail("'exact' sizes can't be negative", advanceBy: count)
    }
    return .succ(.init(exact: exact, x: x.value, y: y.value, xIsPercent: x.isPercent, yIsPercent: y.isPercent), advanceBy: count)
}
