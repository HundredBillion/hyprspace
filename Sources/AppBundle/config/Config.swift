import AppKit
import Common
import HotKey
import OrderedCollections

func getDefaultConfigUrlFromProject() -> URL {
    var url = URL(filePath: #filePath)
    check(FileManager.default.fileExists(atPath: url.path))
    while !FileManager.default.fileExists(atPath: url.appending(component: ".git").path) {
        url.deleteLastPathComponent()
    }
    let projectRoot: URL = url
    return projectRoot.appending(component: "docs/config-examples/default-config.toml")
}

var defaultConfigUrl: URL {
    if isUnitTest {
        return getDefaultConfigUrlFromProject()
    } else {
        return Bundle.main.url(forResource: "default-config", withExtension: "toml")
            // Useful for debug builds that are not app bundles
            ?? getDefaultConfigUrlFromProject()
    }
}
@MainActor let defaultConfig: Config = {
    let parsedConfig = parseConfig(Result { try String(contentsOf: defaultConfigUrl, encoding: .utf8) }.getOrDie())
    if !parsedConfig.errors.isEmpty {
        die("Can't parse default config: \(parsedConfig.errors)")
    }
    return parsedConfig.config
}()
@MainActor var config: Config = defaultConfig // todo move to Ctx?
@MainActor var configUrl: URL = defaultConfigUrl

struct Config: Withable {
    var configVersion: ConfigVersion = ._1
    var _afterLoginCommand: [any Command] = []
    var afterStartupCommand: Shell<any Command> = .empty
    var _indentForNestedContainersWithTheSameOrientation: Void = ()
    var enableNormalizationFlattenContainers: Bool = true
    var _nonEmptyWorkspacesRootContainersLayoutOnStartup: Void = ()
    var defaultRootContainerLayout: Layout = .tiles
    var defaultRootContainerOrientation: DefaultContainerOrientation = .auto
    var newWindowPlacement: NewWindowPlacement = .dwindle
    var startAtLogin: Bool = false
    var autoReloadConfig: Bool = false
    var automaticallyUnhideMacosHiddenApps: Bool = false
    var accordionPadding: Int = 30
    var enableNormalizationOppositeOrientationForNestedContainers: Bool = true
    var persistentWorkspaces: OrderedSet<String> = []
    var execOnWorkspaceChange: [String] = [] // todo deprecate
    var keyMapping = KeyMapping()
    var execConfig: ExecConfig = ExecConfig()
    var focusFollowsMouse: FocusFollowsMouse = FocusFollowsMouse()
    /// Hold the modifier and drag a window with the left mouse button to move it, with the right one to resize it
    var mouseDragModifier: MouseDragModifier? = nil
    var border: BorderConfig = BorderConfig()
    var animations: AnimationsConfig = AnimationsConfig()

    var onFocusChanged: Shell<any Command> = .empty
    // var onFocusedWorkspaceChanged: [any Command] = []
    var onFocusedMonitorChanged: Shell<any Command> = .empty

    var gaps: Gaps = .zero
    var workspaceToMonitorForceAssignment: [String: [MonitorDescription]] = [:]
    var modes: [String: Mode] = [:]
    var onWindowDetected: [WindowDetectedCallback] = []
    var windowRules: [WindowDetectedCallback] = []
    var onModeChanged: Shell<any Command> = .empty
}

struct FocusFollowsMouse: Withable {
    var enabled: Bool = false
}

/// Borders around windows.
/// Hyprland: general:border_size, general:col.active_border, general:col.inactive_border, decoration:rounding
struct BorderConfig: Withable, Equatable {
    var enabled: Bool = true
    var width: Int = 2
    /// nil means "no border"
    var activeColor: BorderColor? = BorderColor(RgbaColor(red: 0x33 / 255.0, green: 0xcc / 255.0, blue: 0xff / 255.0, alpha: 0xee / 255.0))
    /// nil means "no border"
    var inactiveColor: BorderColor? = BorderColor(RgbaColor(red: 0x59 / 255.0, green: 0x59 / 255.0, blue: 0x59 / 255.0, alpha: 0xaa / 255.0))
    var rounding: Int = 10
    /// A window that is alone on its workspace has no border: there is nothing to tell it apart from
    var hideOnSingleWindow: Bool = false
}

/// A solid color or a linear gradient. Hyprland: 'rgba(33ccffee) rgba(00ff99ee) 45deg'
struct BorderColor: Equatable {
    var colors: [RgbaColor]
    var angleDegrees: Double

    init(_ color: RgbaColor) {
        colors = [color]
        angleDegrees = 0
    }

    init(colors: [RgbaColor], angleDegrees: Double) {
        self.colors = colors
        self.angleDegrees = angleDegrees
    }

    static let maxColors = 10
    static let supportedFormats = "One color: '#rrggbb', '#rrggbbaa', 'rgb(rrggbb)', 'rgba(rrggbbaa)', '0xaarrggbb'. " +
        "Gradient: several colors and an optional angle separated by spaces: 'rgba(33ccffee) rgba(00ff99ee) 45deg'. " +
        "No border: 'none'"

    /// - Returns: `.some(nil)` for 'none', `nil` if the string can't be parsed
    static func parse(_ raw: String) -> BorderColor?? {
        var words = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        if words == ["none"] { return .some(nil) }
        var angle: Double = 0
        if let last = words.last, last.lowercased().hasSuffix("deg") {
            guard let parsed = Double(last.dropLast(3)), parsed.isFinite else { return nil }
            angle = parsed
            words.removeLast()
        }
        let colors = words.compactMap(RgbaColor.parse)
        if colors.isEmpty || colors.count != words.count || colors.count > maxColors { return nil }
        return BorderColor(colors: colors, angleDegrees: angle)
    }
}

/// Hyprland: animations:enabled
struct AnimationsConfig: Withable, Equatable {
    var enabled: Bool = true
    var durationMs: Int = 150
    /// New windows pop in: they grow to their size
    var windowOpen: Bool = true
    /// Windows slide in and out when the workspace is switched. Off by default: the workspace is switched instantly
    var workspaceSwitch: Bool = false
}

struct RgbaColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    /// Supported formats: '#rrggbb', '#rrggbbaa', 'rgb(rrggbb)', 'rgba(rrggbbaa)', '0xaarrggbb'
    static func parse(_ raw: String) -> RgbaColor? {
        let str = raw.trim().lowercased()
        func hex(_ str: Substring) -> [Double]? {
            guard str.count == 6 || str.count == 8, str.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
            let chars = Array(str)
            return stride(from: 0, to: chars.count, by: 2).map { Double(UInt8(String(chars[$0 ... $0 + 1]), radix: 16) ?? 0) / 255.0 }
        }
        let components: [Double]? // r, g, b, [a]
        if str.hasPrefix("#") {
            components = hex(str.dropFirst())
        } else if str.hasPrefix("rgba("), str.hasSuffix(")"), str.count == "rgba()".count + 8 {
            components = hex(str.dropFirst("rgba(".count).dropLast())
        } else if str.hasPrefix("rgb("), str.hasSuffix(")"), str.count == "rgb()".count + 6 {
            components = hex(str.dropFirst("rgb(".count).dropLast())
        } else if str.hasPrefix("0x"), str.count == 10 {
            components = hex(str.dropFirst(2)).map { [$0[1], $0[2], $0[3], $0[0]] } // aarrggbb
        } else {
            components = nil
        }
        guard let components else { return nil }
        return RgbaColor(red: components[0], green: components[1], blue: components[2], alpha: components.getOrNil(atIndex: 3) ?? 1)
    }
}

enum ConfigVersion: Int, Comparable, CaseIterable, Sendable, CustomStringConvertible {
    case _1 = 1
    case _2 = 2

    static let max = allCases.max().orDie()
    static let min = allCases.min().orDie()
    static func < (lhs: ConfigVersion, rhs: ConfigVersion) -> Bool { lhs.rawValue < rhs.rawValue }

    var description: String { rawValue.description }
}

enum DefaultContainerOrientation: String {
    case horizontal, vertical, auto
}

enum NewWindowPlacement: String, CaseIterable {
    /// The new window becomes the next sibling of the most recently used window
    case sibling
    /// Hyprland-like. The new window splits the most recently used window in half.
    /// The split goes along the longer side of the window that is being split
    case dwindle
    /// Hyprland-like. The first window is the master. All the other windows are stacked next to the master
    case master
}
