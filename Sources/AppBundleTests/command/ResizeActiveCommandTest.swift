@testable import AppBundle
import AppKit
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct ResizeActiveCommandTest {
    init() { setUpWorkspacesForTests() }

    @Test func testParse() {
        #expect(parseCommand("resizeactive 10 0").errorOrNil == nil)
        #expect(parseCommand("resizeactive -10 -20").errorOrNil == nil)
        #expect(parseCommand("resizeactive exact 800 600").errorOrNil == nil)
        #expect(parseCommand("resizeactive 10").errorOrNil != nil)
        #expect(parseCommand("resizeactive exact -1 5").errorOrNil != nil)
        #expect(parseCommand("resizeactive a b").errorOrNil != nil)
        // Used to crash the server with an integer overflow
        #expect(parseCommand("resizeactive -9223372036854775808 0").errorOrNil != nil)
        #expect(parseCommand("resizeactive 0 9223372036854775807").errorOrNil != nil)
    }

    @Test func testExtremeValuesDoNotCrash() async {
        let root = Workspace.get(byName: name).rootTilingContainer
        assertEquals(TestWindow.new(id: 1, parent: root, adaptiveWeight: 100).focusWindow(), true)
        TestWindow.new(id: 2, parent: root, adaptiveWeight: 100)
        // Bypasses the parser on purpose
        var args = ResizeActiveCmdArgs(rawArgs: [])
        args.params = .initialized(.init(exact: false, x: Int.min, y: Int.min))
        _ = await ResizeActiveCommand(args: args).run(.defaultEnv, .emptyStdin)
    }

    @Test func testResize() async {
        let root = Workspace.get(byName: name).rootTilingContainer
        let window1 = TestWindow.new(id: 1, parent: root, adaptiveWeight: 100)
        let window2 = TestWindow.new(id: 2, parent: root, adaptiveWeight: 100)
        assertEquals(window1.focusWindow(), true)

        await parseCommand("resizeactive 20 0").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window1.getWeight(.h), 120)
        assertEquals(window2.getWeight(.h), 80)

        await parseCommand("resizeactive -40 0").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window1.getWeight(.h), 80)
        assertEquals(window2.getWeight(.h), 120)

        await parseCommand("resizeactive exact 150 0").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window1.getWeight(.h), 150)
        assertEquals(window2.getWeight(.h), 50)
    }
}
