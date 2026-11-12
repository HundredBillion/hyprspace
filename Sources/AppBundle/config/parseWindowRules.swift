import Common

/// Hyprland-like window rules: 'RULE, MATCHER[, MATCHER]...'
///
///     windowrule = [
///         'float, class:^(Calculator)$',
///         'workspace 3 silent, class:Slack, title:.*Huddle.*',
///     ]
///
/// Rules: float, tile, pin, fullscreen, workspace <name> [silent]
/// Matchers: class:<regex> (app name or app bundle ID), title:<regex>. Like in Hyprland, the regex must match the full string
func parseWindowRules(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> [WindowDetectedCallback] {
    guard let array = raw.asArrayOrNil else {
        c.errors += [expectedActualTypeDiagnostic(expected: .array, actual: raw.tomlType, backtrace)]
        return []
    }
    var result: [WindowDetectedCallback] = []
    for (index, raw) in array.enumerated() {
        let backtrace = backtrace + .index(index)
        guard let str = raw.asStringOrNil else {
            c.errors += [expectedActualTypeDiagnostic(expected: .string, actual: raw.tomlType, backtrace)]
            continue
        }
        switch parseWindowRule(str) {
            case .success(let callbacks): result += callbacks
            case .failure(let msg): c.errors.append(.init(backtrace, msg))
        }
    }
    return result
}

private func parseWindowRule(_ raw: String) -> ResOrStr<[WindowDetectedCallback]> {
    Result { () throws(String) in
        let parts = splitWindowRule(raw)
        guard let rule = parts.first, parts.count >= 2 else {
            throw "Can't parse window rule '\(raw)'. Expected format: 'RULE, MATCHER[, MATCHER]...'"
        }
        var matcher = LegacyWindowDetectedCallbackMatcher()
        for rawMatcher in parts.dropFirst() {
            if rawMatcher.hasPrefix("class:") {
                matcher.appIdOrNameRegex = try fullMatchRegex(String(rawMatcher.dropFirst("class:".count))).get()
            } else if rawMatcher.hasPrefix("title:") {
                matcher.windowTitleRegexSubstring = try fullMatchRegex(String(rawMatcher.dropFirst("title:".count))).get()
            } else {
                throw "Can't parse window rule matcher '\(rawMatcher)'. Supported matchers: 'class:<regex>', 'title:<regex>'"
            }
        }

        let ruleWords = rule.split(separator: " ").map(String.init)
        let commands: [String]
        switch ruleWords.first {
            case "float" where ruleWords.count == 1: commands = ["layout floating"]
            case "tile" where ruleWords.count == 1: commands = ["layout tiling"]
            case "pin" where ruleWords.count == 1: commands = ["layout floating", "pin on"]
            case "fullscreen" where ruleWords.count == 1: commands = ["fullscreen on"]
            case "workspace" where ruleWords.count == 2 || (ruleWords.count == 3 && ruleWords[2] == "silent"):
                // Windows are always moved silently. The focus follows the window anyway if the window is focused
                commands = ["move-node-to-workspace \(hyprlandWorkspaceName(ruleWords[1]))"]
            default:
                throw "Can't parse window rule '\(rule)'. Supported rules: float, tile, pin, fullscreen, workspace <name> [silent]"
        }
        return try commands.map { (command: String) throws(String) in
            let run = try parseCommand(command, allowExecAndForget: false, allowEval: false).toResult().get()
            // Like in Hyprland, all the matching rules are applied
            return WindowDetectedCallback(matcher: .legacy(matcher), checkFurtherCallbacks: true, rawRun: run)
        }
    }
}

/// Splits 'RULE, MATCHER, MATCHER' by commas. A comma only separates parts if it is followed by something that
/// looks like a matcher ('word:'). That's how regexes are allowed to contain commas: 'title:a{1,3}', 'class:Foo, Inc'
func splitWindowRule(_ raw: String) -> [String] {
    var parts: [String] = []
    for chunk in raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init) {
        let trimmed = chunk.trim()
        let word = trimmed.prefix(while: { $0.isLetter })
        let looksLikeMatcher = !word.isEmpty && trimmed.dropFirst(word.count).first == ":"
        // The first chunk is the rule. The chunk right after the rule always starts the first matcher
        if parts.count <= 1 || looksLikeMatcher {
            parts.append(chunk)
        } else {
            parts[parts.count - 1] += "," + chunk // The comma belongs to the regex of the previous matcher
        }
    }
    return parts.map { $0.trim() }
}

private func fullMatchRegex(_ raw: String) -> ResOrStr<CaseInsensitiveRegex> {
    // The regex must be valid on its own. Otherwise, something like 'a)|(b' would escape the anchors below
    CaseInsensitiveRegex.new(raw).flatMap { _ in CaseInsensitiveRegex.new("^(?:\(raw))$") }
}
