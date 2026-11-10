@testable import AppBundle
import AppKit
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct MasterPlacementTest {
    init() {
        setUpWorkspacesForTests()
        config.newWindowPlacement = .master
    }

    private func detectNewWindow(id: OpaqueWindowId, on workspace: Workspace) async throws {
        // Bind outside of the workspace first to not disturb the MRU of the workspace
        let window = TestWindow.new(id: id, parent: macosPopupWindowsContainer)
        try await window.relayoutWindow(on: workspace, .cancellable, forceTile: true)
    }

    @Test func testMasterAndStack() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer

        try await detectNewWindow(id: 0, on: workspace)
        assertEquals(root.layoutDescription, .h_tiles([.window(0)]))

        try await detectNewWindow(id: 1, on: workspace)
        assertEquals(root.layoutDescription, .h_tiles([.window(0), .window(1)]))

        try await detectNewWindow(id: 2, on: workspace)
        assertEquals(root.layoutDescription, .h_tiles([
            .window(0),
            .v_tiles([.window(1), .window(2)]),
        ]))

        try await detectNewWindow(id: 3, on: workspace)
        assertEquals(root.layoutDescription, .h_tiles([
            .window(0),
            .v_tiles([.window(1), .window(2), .window(3)]),
        ]))
    }

    @Test func testNewWindowGoesToStackEvenIfMasterIsFocused() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let master = TestWindow.new(id: 0, parent: root)
        TestWindow.new(id: 1, parent: root)
        assertEquals(master.focusWindow(), true)

        try await detectNewWindow(id: 2, on: workspace)
        assertEquals(root.layoutDescription, .h_tiles([
            .window(0),
            .v_tiles([.window(1), .window(2)]),
        ]))
    }

    @Test func testParseConfig() {
        let result = parseConfig("new-window-placement = 'master'")
        assertEquals(result.errors, [])
        assertEquals(result.config.newWindowPlacement, .master)
    }
}
