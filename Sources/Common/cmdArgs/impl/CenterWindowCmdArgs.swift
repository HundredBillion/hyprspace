public struct CenterWindowCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .centerwindow,
        help: centerwindow_help_generated,
        flags: [
            "--window-id": windowIdSubArgParser(),
        ],
        posArgs: [],
    )
}
