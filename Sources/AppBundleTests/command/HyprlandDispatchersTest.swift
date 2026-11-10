@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct HyprlandDispatchersTest {
    init() {
        setUpWorkspacesForTests()
        _prevFocusedWorkspaceName = nil
    }

    @Test func testParse() {
        testParseSingleCommandSucc("movefocus l", FocusCmdArgs(rawArgs: [], cardinalOrDfsDirection: .direction(.left)))
        testParseSingleCommandSucc("movefocus right", FocusCmdArgs(rawArgs: [], cardinalOrDfsDirection: .direction(.right)))
        testParseSingleCommandSucc("movetoworkspacesilent 5", MoveNodeToWorkspaceCmdArgs(workspace: "5"))
        testParseSingleCommandSucc(
            "togglespecialworkspace",
            WorkspaceCmdArgs(target: .direct(.parse("special").getOrDie()), autoBackAndForth: true),
        )
        testParseSingleCommandSucc(
            "togglespecialworkspace music",
            WorkspaceCmdArgs(target: .direct(.parse("special-music").getOrDie()), autoBackAndForth: true),
        )
        #expect(parseCommand("killactive").errorOrNil == nil)
        #expect(parseCommand("togglefloating").errorOrNil == nil)
        #expect(parseCommand("togglesplit").errorOrNil == nil)
        #expect(parseCommand("focuscurrentorlast").errorOrNil == nil)
        #expect(parseCommand("cyclenext").errorOrNil == nil)
        #expect(parseCommand("cyclenext prev").errorOrNil == nil)
        #expect(parseCommand("movewindow u").errorOrNil == nil)
        #expect(parseCommand("swapwindow d").errorOrNil == nil)
        #expect(parseCommand("focusmonitor l").errorOrNil == nil)
        #expect(parseCommand("movetoworkspace special:music").errorOrNil == nil)
        #expect(parseCommand("exec open -a Terminal").errorOrNil == nil)
    }

    @Test func testParseErrors() {
        assertEquals(parseCommand("movefocus x").errorOrNil, "movefocus: can't parse direction 'x'. Possible values: (l|r|u|d)")
        assertEquals(parseCommand("movefocus").errorOrNil, "movefocus: expected exactly one argument: (l|r|u|d)")
        assertEquals(parseCommand("killactive now").errorOrNil, "killactive: unexpected arguments [\"now\"]")
        assertEquals(parseCommand("notadispatcher").errorOrNil, "Unrecognized subcommand 'notadispatcher'")
    }

    @Test func testMoveFocus() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }
        await parseCommand("movefocus r").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 2)
    }

    @Test func testMoveToWorkspaceFollowsWindow() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }
        await parseCommand("movetoworkspace 7").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.workspace.name, "7")
        assertEquals(globalFocus.windowOrNil?.windowId, 1)
    }

    @Test func testToggleSpecialWorkspace() async {
        let original = globalFocus.workspace.name
        // The previously focused workspace is recorded by the refresh session that follows every command in the real app
        await checkOnFocusChangedCallbacks_nonCancellable()
        await parseCommand("togglespecialworkspace").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.workspace.name, "special")
        await checkOnFocusChangedCallbacks_nonCancellable()
        await parseCommand("togglespecialworkspace").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.workspace.name, original)
    }
}
