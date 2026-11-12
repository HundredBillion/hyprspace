import Common

private let borderParserTable: [String: any ParserProtocol<BorderConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "width": Parser(\.width, parseSmallNonNegativeInt),
    "active-color": Parser(\.activeColor, parseColor),
    "rounding": Parser(\.rounding, parseSmallNonNegativeInt),
]

func parseBorderConfig(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> BorderConfig {
    parseNonEmptyTable(raw, BorderConfig(), borderParserTable, backtrace, &c)
}

private let animationsParserTable: [String: any ParserProtocol<AnimationsConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "duration-ms": Parser(\.durationMs, parseAnimationDuration),
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

private func parseColor(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<RgbaColor> {
    parseString(raw, backtrace).flatMap {
        RgbaColor.parse($0).toResult(.init(
            backtrace,
            "Can't parse color '\($0)'. Supported formats: '#rrggbb', '#rrggbbaa', 'rgb(rrggbb)', 'rgba(rrggbbaa)', '0xaarrggbb'",
        ))
    }
}
