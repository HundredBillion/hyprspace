@testable import AppBundle
import AppKit
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct ToggleSpecialWorkspaceCommandTest {
    init() { setUpWorkspacesForTests() }

    @Test func testParse() {
        #expect(parseCommand("togglespecialworkspace").errorOrNil == nil)
        #expect(parseCommand("togglespecialworkspace magic").errorOrNil == nil)
        #expect(parseCommand("togglespecialworkspace a:b").errorOrNil != nil)
        #expect(parseCommand("togglespecialworkspace ''").errorOrNil != nil)
    }

    @Test func testShowAndHide() async {
        let workspace = globalFocus.workspace
        let tiled = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let scratch = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        assertEquals(scratch.focusWindow(), true)

        await parseCommand("movetoworkspacesilent special").cmdOrDie.run(.defaultEnv, .emptyStdin)
        let special = Workspace.get(byName: "special")
        assertEquals(scratch.nodeWorkspace, special)
        assertEquals(tiled.focusWindow(), true)

        // Show
        let show = await parseCommand("togglespecialworkspace").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(show.exitCode.rawValue, 0)
        assertEquals(globalFocus.workspace, workspace) // The current workspace stays visible
        assertEquals(scratch.nodeWorkspace, workspace)
        assertEquals(scratch.isFloating, true)
        assertEquals(scratch.isPinned, true)
        assertEquals(scratch.shownSpecialWorkspace, "special")
        assertEquals(globalFocus.windowOrNil, scratch)
        let monitor = workspace.workspaceMonitorInfo.visibleRect
        let rect = try! await scratch.getAxRect(.cancellable).orDie()
        assertEquals(rect.width, monitor.width * 0.8)
        assertEquals(rect.height, monitor.height * 0.8)

        // Hide
        let hide = await parseCommand("togglespecialworkspace").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(hide.exitCode.rawValue, 0)
        // The empty special workspace may have been garbage collected and recreated, so compare by name
        assertEquals(scratch.nodeWorkspace?.name, "special")
        assertEquals(scratch.isPinned, false)
        assertEquals(scratch.shownSpecialWorkspace, nil)
        assertEquals(globalFocus.workspace, workspace)
        assertEquals(globalFocus.windowOrNil, tiled)
    }

    @Test func testShownSpecialWorkspaceFollowsWorkspaceSwitch() async {
        let workspace = globalFocus.workspace
        let scratch = TestWindow.new(id: 1, parent: Workspace.get(byName: "special-magic").rootTilingContainer)
        await parseCommand("togglespecialworkspace magic").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(scratch.nodeWorkspace, workspace)

        let other = Workspace.get(byName: "other")
        assertEquals(other.focusWorkspace(), true)
        assertEquals(scratch.nodeWorkspace, other)

        await parseCommand("togglespecialworkspace magic").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(scratch.nodeWorkspace?.name, "special-magic")
    }

    @Test func testTilingAShownWindowReleasesItFromTheSpecialWorkspace() async {
        let workspace = globalFocus.workspace
        let scratch = TestWindow.new(id: 1, parent: Workspace.get(byName: "special").rootTilingContainer)
        await parseCommand("togglespecialworkspace").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(scratch.isPinned, true)

        // The user tiles the scratchpad window: it becomes a regular window of the current workspace
        await parseCommand("layout tiling").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(scratch.isFloating, false)
        assertEquals(scratch.isPinned, false)
        assertEquals(scratch.shownSpecialWorkspace, nil)
        assertEquals(scratch.nodeWorkspace, workspace)

        // Floating it again must not silently pin it
        await parseCommand("layout floating").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(scratch.isPinned, false)
        assertEquals(Workspace.get(byName: "other").focusWorkspace(), true)
        assertEquals(scratch.nodeWorkspace, workspace)
    }

    @Test func testEmptySpecialWorkspaceFails() async {
        let result = await parseCommand("togglespecialworkspace").cmdOrDie.run(.defaultEnv, .emptyStdin)
        #expect(result.exitCode.rawValue != 0)
    }

    @Test func testSlots() {
        let slots = specialWorkspaceSlots(Rect(topLeftX: 0, topLeftY: 0, width: 1000, height: 500), count: 2)
        assertEquals(slots.count, 2)
        assertEquals(slots[0].topLeftX, 100)
        assertEquals(slots[0].topLeftY, 50)
        assertEquals(slots[0].width, 395)
        assertEquals(slots[0].height, 400)
        assertEquals(slots[1].topLeftX, 505)
    }
}
