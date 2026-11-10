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

    @Test func testSingleTallWindowChangesRootOrientation() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let window0 = TestWindow.new(id: 0, parent: root)
        assertEquals(window0.focusWindow(), true)
        window0.lastAppliedLayoutPhysicalRect = rect(width: 1000, height: 1600)

        try await detectNewWindow(id: 1, on: workspace)
        assertEquals(root.layoutDescription, .v_tiles([.window(0), .window(1)]))
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
