@testable import AppBundle
import AppKit
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct DwindlePlacementTest {
    init() {
        setUpWorkspacesForTests()
        config.newWindowPlacement = .dwindle
    }

    /// Simulates detection of a new tiling window
    @discardableResult
    private func detectNewWindow(id: OpaqueWindowId, on workspace: Workspace) async throws -> TestWindow {
        // Bind outside of the workspace first to not disturb the MRU of the workspace
        let window = TestWindow.new(id: id, parent: macosPopupWindowsContainer)
        try await window.relayoutWindow(on: workspace, .cancellable, forceTile: true)
        return window
    }

    private func rect(width: CGFloat, height: CGFloat) -> Rect {
        Rect(topLeftX: 0, topLeftY: 0, width: width, height: height)
    }

    @Test func testDefaultPlacementIsSibling() async throws {
        config.newWindowPlacement = .sibling
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        TestWindow.new(id: 0, parent: root)
        let window1 = TestWindow.new(id: 1, parent: root)
        assertEquals(window1.focusWindow(), true)
        window1.lastAppliedLayoutPhysicalRect = rect(width: 800, height: 1000)

        try await detectNewWindow(id: 2, on: workspace)
        assertEquals(root.layoutDescription, .h_tiles([.window(0), .window(1), .window(2)]))
    }

    @Test func testSingleWindowReusesRootContainer() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let window0 = TestWindow.new(id: 0, parent: root)
        assertEquals(window0.focusWindow(), true)
        window0.lastAppliedLayoutPhysicalRect = rect(width: 1600, height: 1000)

        try await detectNewWindow(id: 1, on: workspace)
        assertEquals(root.layoutDescription, .h_tiles([.window(0), .window(1)]))
    }

    @Test func testSingleWindowKeepsExplicitRootOrientation() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let window0 = TestWindow.new(id: 0, parent: root)
        assertEquals(window0.focusWindow(), true)
        // The window is tall, but the root orientation is the choice of the user. Dwindle must not override it
        window0.lastAppliedLayoutPhysicalRect = rect(width: 1000, height: 1600)

        try await detectNewWindow(id: 1, on: workspace)
        assertEquals(root.layoutDescription, .h_tiles([.window(0), .window(1)]))
    }

    @Test func testSpiral() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        TestWindow.new(id: 0, parent: root)
        let window1 = TestWindow.new(id: 1, parent: root)
        assertEquals(window1.focusWindow(), true)

        window1.lastAppliedLayoutPhysicalRect = rect(width: 800, height: 1000)
        let window2 = try await detectNewWindow(id: 2, on: workspace)
        assertEquals(root.layoutDescription, .h_tiles([
            .window(0),
            .v_tiles([.window(1), .window(2)]),
        ]))

        // The new window is the most recent one, so the next window splits it
        window2.lastAppliedLayoutPhysicalRect = rect(width: 800, height: 500)
        try await detectNewWindow(id: 3, on: workspace)
        assertEquals(root.layoutDescription, .h_tiles([
            .window(0),
            .v_tiles([
                .window(1),
                .h_tiles([.window(2), .window(3)]),
            ]),
        ]))
    }

    @Test func testSplitsFocusedWindowNotTheLastOne() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let window0 = TestWindow.new(id: 0, parent: root)
        TestWindow.new(id: 1, parent: root)
        assertEquals(window0.focusWindow(), true)
        window0.lastAppliedLayoutPhysicalRect = rect(width: 800, height: 1000)

        try await detectNewWindow(id: 2, on: workspace)
        assertEquals(root.layoutDescription, .h_tiles([
            .v_tiles([.window(0), .window(2)]),
            .window(1),
        ]))
    }

    @Test func testSplitAlongParentOrientationKeepsTreeFlat() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let window0 = TestWindow.new(id: 0, parent: root, adaptiveWeight: 2000)
        let window1 = TestWindow.new(id: 1, parent: root, adaptiveWeight: 2000)
        assertEquals(window1.focusWindow(), true)
        // Ultrawide monitor: half of the screen is still wider than tall
        window1.lastAppliedLayoutPhysicalRect = rect(width: 2000, height: 1000)

        let window2 = try await detectNewWindow(id: 2, on: workspace)
        assertEquals(root.layoutDescription, .h_tiles([.window(0), .window(1), .window(2)]))
        assertEquals(window0.getWeight(.h), 2000)
        assertEquals(window1.getWeight(.h), 1000)
        assertEquals(window2.getWeight(.h), 1000)
    }

    @Test func testUnknownRectFallsBackToOppositeOrientation() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        TestWindow.new(id: 0, parent: root)
        assertEquals(TestWindow.new(id: 1, parent: root).focusWindow(), true)

        try await detectNewWindow(id: 2, on: workspace)
        assertEquals(root.layoutDescription, .h_tiles([
            .window(0),
            .v_tiles([.window(1), .window(2)]),
        ]))
    }

    @Test func testAccordionParentIsNotSplit() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        root.layout = .accordion
        TestWindow.new(id: 0, parent: root)
        let window1 = TestWindow.new(id: 1, parent: root)
        assertEquals(window1.focusWindow(), true)
        window1.lastAppliedLayoutPhysicalRect = rect(width: 800, height: 1000)

        try await detectNewWindow(id: 2, on: workspace)
        assertEquals(root.layoutDescription, .h_accordion([.window(0), .window(1), .window(2)]))
    }

    @Test func testStartupDwindlesWithoutKnownSizes() async throws {
        // At startup the windows that are already open are detected one after another, before any layout pass,
        // so their sizes are unknown. They must still dwindle instead of becoming a row of narrow columns
        let workspace = Workspace.get(byName: name)
        try await $refreshSessionEvent.withValue(.startup) {
            for id: OpaqueWindowId in [0, 1, 2, 3] {
                assertEquals(try await detectNewWindow(id: id, on: workspace).focusWindow(), true)
            }
        }
        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([
            .window(0),
            .v_tiles([
                .window(1),
                .h_tiles([.window(2), .window(3)]),
            ]),
        ]))
    }

    /// Workspace "dst" has two windows side by side. Window 1 is its selected (most recent) window.
    /// Window 2 is focused on workspace "src"
    private func setUpMoveToWorkspace() -> TilingContainer {
        let target = Workspace.get(byName: "dst").rootTilingContainer
        TestWindow.new(id: 0, parent: target)
        let window1 = TestWindow.new(id: 1, parent: target)
        assertEquals(window1.focusWindow(), true)
        window1.lastAppliedLayoutPhysicalRect = rect(width: 756, height: 948) // Half of a laptop screen: taller than wide
        assertEquals(TestWindow.new(id: 2, parent: Workspace.get(byName: "src").rootTilingContainer).focusWindow(), true)
        return target
    }

    @Test func testMovedWindowSplitsTheSelectedWindowOfTheTargetWorkspace() async {
        let target = setUpMoveToWorkspace()
        await parseCommand("move-node-to-workspace dst").cmdOrDie.run(.defaultEnv, .emptyStdin)
        // Not a third narrow column: the selected window is split along its longer side, like for a new window
        assertEquals(target.layoutDescription, .h_tiles([
            .window(0),
            .v_tiles([.window(1), .window(2)]),
        ]))
    }

    @Test func testMovedWindowIsAppendedWithSiblingPlacement() async {
        config.newWindowPlacement = .sibling
        let target = setUpMoveToWorkspace()
        await parseCommand("move-node-to-workspace dst").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(target.layoutDescription, .h_tiles([.window(0), .window(1), .window(2)]))
    }

    @Test func testParseConfig() {
        let dwindle = parseConfig("new-window-placement = 'dwindle'")
        assertEquals(dwindle.errors, [])
        assertEquals(dwindle.config.newWindowPlacement, .dwindle)

        assertEquals(parseConfig("").config.newWindowPlacement, .dwindle)

        let sibling = parseConfig("new-window-placement = 'sibling'")
        assertEquals(sibling.errors, [])
        assertEquals(sibling.config.newWindowPlacement, .sibling)

        let bogus = parseConfig("new-window-placement = 'bogus'")
        assertEquals(
            bogus.strErrors,
            ["[ERROR] new-window-placement: Can't parse new window placement 'bogus'. Possible values: sibling|dwindle|master"],
        )
    }
}
