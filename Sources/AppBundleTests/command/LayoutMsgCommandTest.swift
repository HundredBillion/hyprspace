@testable import AppBundle
import AppKit
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct LayoutMsgCommandTest {
    init() { setUpWorkspacesForTests() }

    @Test func testParse() {
        #expect(parseCommand("layoutmsg swapwithmaster").errorOrNil == nil)
        #expect(parseCommand("layoutmsg mfact 0.05").errorOrNil == nil)
        #expect(parseCommand("layoutmsg mfact -0.05").errorOrNil == nil)
        #expect(parseCommand("layoutmsg mfact exact 0.6").errorOrNil == nil)
        #expect(parseCommand("layoutmsg mfact exact 1.5").errorOrNil != nil)
        #expect(parseCommand("layoutmsg bogus").errorOrNil != nil)
        // NaN and infinity used to be accepted and poisoned the weights of the workspace for good
        #expect(parseCommand("layoutmsg mfact nan").errorOrNil != nil)
        #expect(parseCommand("layoutmsg mfact inf").errorOrNil != nil)
        #expect(parseCommand("layoutmsg mfact exact nan").errorOrNil != nil)
        #expect(parseCommand("layoutmsg mfact 5").errorOrNil != nil)
        #expect(parseCommand("layoutmsg").errorOrNil != nil)
    }

    @Test func testSwapWithMaster() async {
        let root = Workspace.get(byName: name).rootTilingContainer
        TestWindow.new(id: 0, parent: root)
        let stack = TilingContainer.newVTiles(parent: root, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        TestWindow.new(id: 1, parent: stack)
        let window2 = TestWindow.new(id: 2, parent: stack)
        assertEquals(window2.focusWindow(), true)

        await parseCommand("layoutmsg swapwithmaster").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([.window(2), .v_tiles([.window(1), .window(0)])]))
        assertEquals(globalFocus.windowOrNil?.windowId, 2)

        // The master is focused: swap with the first window of the stack
        await parseCommand("layoutmsg swapwithmaster").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .v_tiles([.window(2), .window(0)])]))
        assertEquals(globalFocus.windowOrNil?.windowId, 2)
    }

    @Test func testMasterFactor() async {
        let root = Workspace.get(byName: name).rootTilingContainer
        let master = TestWindow.new(id: 0, parent: root, adaptiveWeight: 500)
        let stack = TestWindow.new(id: 1, parent: root, adaptiveWeight: 500)
        assertEquals(master.focusWindow(), true)

        await parseCommand("layoutmsg mfact exact 0.6").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(master.getWeight(.h), 600)
        assertEquals(stack.getWeight(.h), 400)

        await parseCommand("layoutmsg mfact -0.1").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(master.getWeight(.h).rounded(), 500)
        assertEquals(stack.getWeight(.h).rounded(), 500)
    }

    @Test func testFocusMaster() async {
        let root = Workspace.get(byName: name).rootTilingContainer
        TestWindow.new(id: 0, parent: root)
        assertEquals(TestWindow.new(id: 1, parent: root).focusWindow(), true)
        await parseCommand("layoutmsg focusmaster").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 0)
    }
}
