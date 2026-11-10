@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct PinCommandTest {
    init() { setUpWorkspacesForTests() }

    @Test func testPinnedWindowFollowsVisibleWorkspace() async {
        let workspaceA = globalFocus.workspace
        TestWindow.new(id: 1, parent: workspaceA.rootTilingContainer)
        let floating = TestWindow.new(id: 2, parent: workspaceA.floatingWindowsContainer)
        assertEquals(floating.focusWindow(), true)

        let result = await parseCommand("pin").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(floating.isPinned, true)

        let workspaceB = Workspace.get(byName: "b")
        let tiledOnB = TestWindow.new(id: 3, parent: workspaceB.rootTilingContainer)
        assertEquals(workspaceB.focusWorkspace(), true)

        assertEquals(floating.nodeWorkspace, workspaceB)
        assertEquals(workspaceA.floatingWindowsContainer.children.isEmpty, true)
        // The pinned window doesn't steal the focus
        assertEquals(workspaceB.mostRecentWindowRecursive, tiledOnB)

        assertEquals(workspaceA.focusWorkspace(), true)
        assertEquals(floating.nodeWorkspace, workspaceA)
    }

    @Test func testUnpinnedWindowStays() async {
        let workspaceA = globalFocus.workspace
        let floating = TestWindow.new(id: 1, parent: workspaceA.floatingWindowsContainer)
        assertEquals(floating.focusWindow(), true)
        await parseCommand("pin").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("pin").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(floating.isPinned, false)

        assertEquals(Workspace.get(byName: "b").focusWorkspace(), true)
        assertEquals(floating.nodeWorkspace, workspaceA)
    }

    @Test func testTilingWindowCantBePinned() async {
        let window = TestWindow.new(id: 1, parent: globalFocus.workspace.rootTilingContainer)
        assertEquals(window.focusWindow(), true)
        let result = await parseCommand("pin").cmdOrDie.run(.defaultEnv, .emptyStdin)
        #expect(result.exitCode.rawValue != 0, "exit code: \(result.exitCode.rawValue), stderr: \(result.stderr)")
        assertEquals(window.isPinned, false)
    }
}
