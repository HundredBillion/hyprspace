import Common

private let borderParserTable: [String: any ParserProtocol<BorderConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "width": Parser(\.width, parseSmallNonNegativeInt),
    "active-color": Parser(\.activeColor, parseBorderColor),
    "inactive-color": Parser(\.inactiveColor, parseBorderColor),
    "rounding": Parser(\.rounding, parseSmallNonNegativeInt),
    "hide-on-single-window": Parser(\.hideOnSingleWindow, parseBool),
]

func parseBorderConfig(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> BorderConfig {
    parseNonEmptyTable(raw, BorderConfig(), borderParserTable, backtrace, &c)
}

private let animationsParserTable: [String: any ParserProtocol<AnimationsConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "duration-ms": Parser(\.durationMs, parseAnimationDuration),
    "window-open": Parser(\.windowOpen, parseBool),
    "workspace-switch": Parser(\.workspaceSwitch, parseBool),
]

func parseAnimationsConfig(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> AnimationsConfig {
    parseNonEmptyTable(raw, AnimationsConfig(), animationsParserTable, backtrace, &c)
}

private func parseSmallNonNegativeInt(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<Int> {
    parseInt(raw, backtrace).flatMap {
        (0 ... 1000).contains($0) ? .success($0) : .failure(.init(backtrace, "The value must be between 0 and 1000"))
    }
}

let maxAnimationDurationMs = 2000

private func parseAnimationDuration(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<Int> {
    parseInt(raw, backtrace).flatMap {
        (0 ... maxAnimationDurationMs).contains($0)
            ? .success($0)
            : .failure(.init(backtrace, "The value must be between 0 and \(maxAnimationDurationMs)"))
    }
}

private func parseBorderColor(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<BorderColor?> {
    parseString(raw, backtrace).flatMap {
        BorderColor.parse($0).toResult(.init(backtrace, "Can't parse color '\($0)'. \(BorderColor.supportedFormats)"))
    }
}
