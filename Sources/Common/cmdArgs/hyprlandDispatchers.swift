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
        case "movetoworkspace": workspace(["move-node-to-workspace", "--focus-follows-window"])
        case "movetoworkspacesilent": workspace(["move-node-to-workspace"])
        case "togglespecialworkspace":
            switch params.count {
                case 0: .success(["workspace", "--auto-back-and-forth", specialWorkspaceName])
                case 1: .success(["workspace", "--auto-back-and-forth", hyprlandWorkspaceName("special:" + params[0])])
                default: .failure("\(dispatcher): expected at most one argument: [<name>]")
            }
        case "cyclenext":
            switch params {
                case []: .success(["focus", "--boundaries-action", "wrap-around-the-workspace", "dfs-next"])
                case ["prev"]: .success(["focus", "--boundaries-action", "wrap-around-the-workspace", "dfs-prev"])
                default: .failure("\(dispatcher): expected at most one argument: [prev]")
            }
        default: nil
    }
}

public let specialWorkspaceName = "special"

/// Hyprland: 'special' and 'special:name'. Colon is replaced, because it's not a nice character for workspace names
private func hyprlandWorkspaceName(_ raw: String) -> String {
    raw.hasPrefix("special:") ? specialWorkspaceName + "-" + raw.dropFirst("special:".count) : raw
}
