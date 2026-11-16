private let focusFollowsMouseParserTable: [String: any ParserProtocol<FocusFollowsMouse>] = [
    "enabled": Parser(\.enabled, parseBool),
]

func parseMouseDragModifier(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<MouseDragModifier?> {
    parseString(raw, backtrace).flatMap {
        MouseDragModifier.parse($0).toResult(.init(
            backtrace,
            "Can't parse modifier '\($0)'. Possible values: 'off' or modifiers joined with a dash: (alt|ctrl|cmd|shift). Example: 'alt-shift'",
        ))
    }
}

func parseFocusFollowsMouse(_ rawConfig: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> FocusFollowsMouse {
    parseNonEmptyTable(rawConfig, FocusFollowsMouse(), focusFollowsMouseParserTable, backtrace, &c)
}
