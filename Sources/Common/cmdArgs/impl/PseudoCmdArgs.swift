public struct PseudoCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .pseudo,
        help: pseudo_help_generated,
        flags: [
            "--window-id": windowIdSubArgParser(),
        ],
        posArgs: [ArgParser(\.toggle, parseToggleEnum)],
    )

    public var toggle: ToggleEnum = .toggle
}
