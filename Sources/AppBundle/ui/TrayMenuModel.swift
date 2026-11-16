import AppKit
import Common

public final class TrayMenuModel: ObservableObject {
    @MainActor public static let shared = TrayMenuModel()

    private init() {}

    @Published var trayText: String = ""
    @Published var trayItems: [TrayItem] = []
    /// Is "layouting" enabled
    @Published var isEnabled: Bool = true
    @Published var workspaces: [WorkspaceViewModel] = []
    @Published var experimentalUISettings: ExperimentalUISettings = ExperimentalUISettings()
    @Published var lastReloadConfigContainedWarnings: Bool = false
    @Published var axPermissionStatus: AxPermissionStatus = .waitingWithPrompt
}

enum AxPermissionStatus: Equatable {
    case granted
    case waiting
    case waitingWithPrompt
}

@MainActor func updateTrayText() {
    let sortedMonitors = globalSortedMonitorInfos
    let focus = globalFocus
    let visibleWorkspaces = sortedMonitors.map { monitor in
        let workspace = monitor.visibleWorkspace
        return (workspace: workspace, hasFullscreenWindows: workspace.allLeafWindowsRecursive.contains { $0.isFullscreen })
    }
    let mode = activeMode?.takeIf { $0 != mainModeId }?.first.map { $0.uppercased() }
    let trayText = (mode.map { "(\($0)) " } ?? "") +
        visibleWorkspaces
        .map {
            let visibleWorkspaceName = $0.hasFullscreenWindows ? "[\($0.workspace.name)]" : $0.workspace.name
            return ($0.workspace == focus.workspace && sortedMonitors.count > 1 ? "*" : "") + visibleWorkspaceName
        }
        .joined(separator: " │ ")
    let workspaces = Workspace.all.map {
        let apps = $0.allLeafWindowsRecursive.map { $0.app.name?.takeIf { !$0.isEmpty } }.filterNotNil().toSet()
        let dash = " - "
        let suffix = switch true {
            case !apps.isEmpty: dash + apps.sorted().joinTruncating(separator: ", ", length: 25)
            case $0.isVisible: dash + $0.workspaceMonitorInfo.name
            default: ""
        }
        let hasFullscreenWindows = $0.allLeafWindowsRecursive.contains { $0.isFullscreen }
        return WorkspaceViewModel(
            name: $0.name,
            suffix: suffix,
            isFocused: focus.workspace == $0,
            isEffectivelyEmpty: $0.isEffectivelyEmpty,
            isVisible: $0.isVisible,
            hasFullscreenWindows: hasFullscreenWindows,
        )
    }
    var items = visibleWorkspaces.map {
        TrayItem(
            type: .workspace,
            name: $0.workspace.name,
            isActive: $0.workspace == focus.workspace,
            hasFullscreenWindows: $0.hasFullscreenWindows,
        )
    }
    if let mode {
        items.insert(TrayItem(type: .mode, name: mode, isActive: true, hasFullscreenWindows: false), at: 0)
    }
    // @Published notifies its observers on every assignment, even if the value is the same.
    // Every notification makes MenuBarLabel re-render the menu bar image, so only assign what has actually changed
    let model = TrayMenuModel.shared
    if model.trayText != trayText { model.trayText = trayText }
    if model.workspaces != workspaces { model.workspaces = workspaces }
    if model.trayItems != items { model.trayItems = items }
}

struct WorkspaceViewModel: Hashable {
    let name: String
    let suffix: String
    let isFocused: Bool
    let isEffectivelyEmpty: Bool
    let isVisible: Bool
    let hasFullscreenWindows: Bool
}

enum TrayItemType: String, Hashable {
    case mode
    case workspace
}

private let validLetters = "A" ... "Z"

struct TrayItem: Hashable, Identifiable {
    let type: TrayItemType
    let name: String
    let isActive: Bool
    let hasFullscreenWindows: Bool
    var systemImageName: String? {
        // System image type is only valid for numbers 0 to 50 and single capital char workspace name
        switch Int(name) {
            case let number?: if !(0 ... 50).contains(number) { return nil }
            case nil where name.count == 1: if !validLetters.contains(name) { return nil }
            default: return nil
        }
        let lowercasedName = name.lowercased()
        return switch type {
            case .mode: "\(lowercasedName).circle"
            case .workspace where isActive: "\(lowercasedName).square.fill"
            case .workspace: "\(lowercasedName).square"
        }
    }
    var id: String {
        return type.rawValue + name
    }
}
