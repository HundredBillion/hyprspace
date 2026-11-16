/// Hyprland dispatchers that are translated to native commands.
/// https://wiki.hypr.land/Configuring/Dispatchers/
///
/// Returns nil if the first argument is not a known Hyprland dispatcher
func translateHyprlandDispatcher(_ args: [String]) -> ResOrStr<[String]>? {
    guard let dispatcher = args.first else { return nil }
    let params = Array(args.dropFirst())
    func noParams(_ result: [String]) -> ResOrStr<[String]> {
        params.isEmpty ? .success(result) : .failure("\(dispatcher): unexpected arguments \(params)")
    }
    func direction(_ prefix: [String]) -> ResOrStr<[String]> {
        guard let raw = params.singleOrNil() else {
            return .failure("\(dispatcher): expected exactly one argument: (l|r|u|d)")
        }
        return switch raw {
            case "l", "left": .success(prefix + ["left"])
            case "r", "right": .success(prefix + ["right"])
            case "u", "up": .success(prefix + ["up"])
            case "d", "down": .success(prefix + ["down"])
            default: .failure("\(dispatcher): can't parse direction '\(raw)'. Possible values: (l|r|u|d)")
        }
    }
    func workspace(_ prefix: [String]) -> ResOrStr<[String]> {
        guard let raw = params.singleOrNil() else {
            return .failure("\(dispatcher): expected exactly one argument: <workspace>")
        }
        return .success(prefix + [hyprlandWorkspaceName(raw)])
    }
    return switch dispatcher {
        case "killactive": noParams(["close"])
        case "movefocus": direction(["focus"])
        case "movewindow": direction(["move"])
        case "swapwindow": direction(["swap"])
        case "focusmonitor": direction(["focus-monitor"])
        case "togglefloating": noParams(["layout", "floating", "tiling"])
        case "togglesplit": noParams(["layout", "horizontal", "vertical"])
        case "focuscurrentorlast": noParams(["focus-back-and-forth"])
        case "movetoworkspace":
            // A window that is moved to a special workspace is hidden until 'togglespecialworkspace'
            params.singleOrNil().map { $0 == specialWorkspaceName || $0.hasPrefix(specialWorkspaceName + ":") } == true
                ? workspace(["move-node-to-workspace"])
                : workspace(["move-node-to-workspace", "--focus-follows-window"])
        case "movetoworkspacesilent": workspace(["move-node-to-workspace"])
        case "cyclenext":
            switch params {
                case []: .success(["focus", "--boundaries-action", "wrap-around-the-workspace", "dfs-next"])
                case ["prev"]: .success(["focus", "--boundaries-action", "wrap-around-the-workspace", "dfs-prev"])
                default: .failure("\(dispatcher): expected at most one argument: [prev]")
            }
        case "swapnext":
            switch params {
                case []: .success(["swap", "--wrap-around", "dfs-next"])
                case ["prev"]: .success(["swap", "--wrap-around", "dfs-prev"])
                default: .failure("\(dispatcher): expected at most one argument: [prev]")
            }
        case "movecurrentworkspacetomonitor": direction(["move-workspace-to-monitor"])
        case "fullscreenstate":
            // fullscreenstate <internal> [<client>]. The state that the app is told about can't be controlled on macOS
            switch params.first {
                case "0" where params.count <= 2: .success(["fullscreen", "off"])
                case "1" where params.count <= 2: .success(["fullscreen", "on"])
                case "2" where params.count <= 2, "3" where params.count <= 2: .success(["fullscreen", "--no-outer-gaps", "on"])
                default: .failure("\(dispatcher): expected arguments: (0|1|2|3) [<client>]")
            }
        case "togglegroup": noParams(["group", "toggle"])
        case "moveoutofgroup": noParams(["group", "move-out"])
        case "moveintogroup": direction(["group", "move-in"])
        case "changegroupactive":
            switch params {
                case [], ["f"]: .success(["group", "next"])
                case ["b"]: .success(["group", "prev"])
                default: .failure("\(dispatcher): expected at most one argument: [f|b]")
            }
        default: nil
    }
}

/// Hyprland forms of the dispatchers that share their name with a native command: 'workspace e+1', 'fullscreen 1'.
/// The native command would understand the arguments differently ('e+1' is a valid workspace name).
///
/// Returns nil if the arguments are not Hyprland specific. The native command is supposed to parse them then
func translateHyprlandFormOfNativeCommand(_ args: [String]) -> ResOrStr<[String]>? {
    guard args.count == 2 else { return nil }
    let param = args[1]
    switch args[0] {
        case "workspace":
            if param == "previous" { return .success(["workspace-back-and-forth"]) }
            if param == specialWorkspaceName { return .success(["togglespecialworkspace"]) }
            if param.hasPrefix(specialWorkspaceName + ":") {
                return .success(["togglespecialworkspace", String(param.dropFirst(specialWorkspaceName.count + 1))])
            }
            return hyprlandRelativeWorkspace(param).map { $0.map { ["workspace"] + $0 } }
        case "movetoworkspace":
            return hyprlandRelativeWorkspace(param).map { $0.map { ["move-node-to-workspace", "--focus-follows-window"] + $0 } }
        case "movetoworkspacesilent":
            return hyprlandRelativeWorkspace(param).map { $0.map { ["move-node-to-workspace"] + $0 } }
        case "fullscreen":
            return switch param {
                case "0", "2": .success(["fullscreen", "--no-outer-gaps"]) // The window covers the gaps
                case "1": .success(["fullscreen"]) // "Maximize". The gaps are preserved
                default: nil
            }
        default:
            return nil
    }
}

/// Hyprland's relative workspaces: '+1', '-1' (by ID), 'r+1' (including empty), 'e+1' (existing), 'm+1' (on the monitor).
/// Workspaces are named and persistent here, that's why all the forms mean the next/prev workspace of the monitor.
/// 'e' and 'm' wrap around like in Hyprland
private func hyprlandRelativeWorkspace(_ raw: String) -> ResOrStr<[String]>? {
    var rest = Substring(raw)
    let selector = rest.first.flatMap { "emr".contains($0) ? $0 : nil }
    if selector != nil { rest = rest.dropFirst() }
    guard let sign = rest.first, sign == "+" || sign == "-", let offset = Int(rest.dropFirst()), rest.count >= 2 else { return nil }
    if offset != 1 { return .failure("workspace '\(raw)': only the offsets +1 and -1 are supported") }
    let wrapAround = selector == "e" || selector == "m"
    return .success((wrapAround ? ["--wrap-around"] : []) + [sign == "+" ? "next" : "prev"])
}

public let specialWorkspaceName = "special"

/// Hyprland: 'special' and 'special:name'. Colon is replaced, because it's not a nice character for workspace names
public func hyprlandWorkspaceName(_ raw: String) -> String {
    raw.hasPrefix("special:") ? specialWorkspaceName + "-" + raw.dropFirst("special:".count) : raw
}
