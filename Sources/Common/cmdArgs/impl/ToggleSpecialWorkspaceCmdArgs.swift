public struct ToggleSpecialWorkspaceCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .togglespecialworkspace,
        help: togglespecialworkspace_help_generated,
        flags: [:],
        posArgs: [ArgParser(\.name, parseSpecialWorkspaceShortName)],
    )

    /// nil means the default unnamed special workspace
    public var name: String? = nil

    public var workspaceName: String { hyprlandWorkspaceName(name.map { "special:" + $0 } ?? specialWorkspaceName) }
}

private func parseSpecialWorkspaceShortName(input: PosArgParserInput) -> ParsedCliArgs<String?> {
    let arg = input.arg
    return !arg.isEmpty && arg.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) || $0 == "-" || $0 == "_" })
        ? .succ(arg, advanceBy: 1)
        : .fail("Special workspace name may only contain letters, digits, '-' and '_'", advanceBy: 1)
}
