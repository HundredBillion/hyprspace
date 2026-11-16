@testable import AppBundle
import AppKit
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct HyprlandFeaturesTest {
    init() { setUpWorkspacesForTests() }

    // MARK: Dispatchers

    @Test func testParseDispatchers() {
        testParseSingleCommandSucc("workspace e+1", WorkspaceCmdArgs(target: .relative(.next)).with(\._wrapAround, true))
        testParseSingleCommandSucc("workspace m-1", WorkspaceCmdArgs(target: .relative(.prev)).with(\._wrapAround, true))
        testParseSingleCommandSucc("workspace +1", WorkspaceCmdArgs(target: .relative(.next)))
        testParseSingleCommandSucc("workspace r-1", WorkspaceCmdArgs(target: .relative(.prev)))
        // Not a Hyprland form. It's a plain workspace name
        testParseSingleCommandSucc("workspace e1", WorkspaceCmdArgs(target: .direct(.parse("e1").getOrDie())))
        assertEquals(parseCommand("workspace +2").errorOrNil, "workspace '+2': only the offsets +1 and -1 are supported")
        #expect(parseCommand("workspace previous").errorOrNil == nil)
        #expect(parseCommand("workspace special").errorOrNil == nil)
        #expect(parseCommand("workspace special:magic").errorOrNil == nil)
        #expect(parseCommand("movetoworkspace +1").errorOrNil == nil)
        #expect(parseCommand("movetoworkspacesilent e-1").errorOrNil == nil)
        #expect(parseCommand("fullscreen 0").errorOrNil == nil)
        #expect(parseCommand("fullscreen 1").errorOrNil == nil)
        #expect(parseCommand("fullscreen on").errorOrNil == nil)
        #expect(parseCommand("fullscreenstate 2").errorOrNil == nil)
        #expect(parseCommand("fullscreenstate 0 0").errorOrNil == nil)
        #expect(parseCommand("fullscreenstate 7").errorOrNil != nil)
        #expect(parseCommand("swapnext").errorOrNil == nil)
        #expect(parseCommand("swapnext prev").errorOrNil == nil)
        #expect(parseCommand("movecurrentworkspacetomonitor l").errorOrNil == nil)
        #expect(parseCommand("togglegroup").errorOrNil == nil)
        #expect(parseCommand("changegroupactive").errorOrNil == nil)
        #expect(parseCommand("changegroupactive b").errorOrNil == nil)
        #expect(parseCommand("moveintogroup r").errorOrNil == nil)
        #expect(parseCommand("moveoutofgroup").errorOrNil == nil)
        #expect(parseCommand("centerwindow").errorOrNil == nil)
        #expect(parseCommand("pseudo").errorOrNil == nil)
        #expect(parseCommand("moveactive -10 20").errorOrNil == nil)
        #expect(parseCommand("moveactive exact -10 20").errorOrNil == nil)
        #expect(parseCommand("moveactive exact 10% 20%").errorOrNil == nil)
        #expect(parseCommand("moveactive 10% 20").errorOrNil != nil)
        #expect(parseCommand("resizeactive exact 50% 50%").errorOrNil == nil)
        #expect(parseCommand("group move-in sideways").errorOrNil != nil)
        #expect(parseCommand("group bogus").errorOrNil != nil)
    }

    @Test func testRelativeWorkspace() async {
        _ = Workspace.get(byName: "a").focusWorkspace()
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        TestWindow.new(id: 2, parent: Workspace.get(byName: "b").rootTilingContainer)
        await parseCommand("workspace e+1").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.workspace.name, "b")
        await parseCommand("workspace m-1").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.workspace.name, "a")
    }

    // MARK: Floating windows

    @Test func testFloatingWindowGeometry() async throws {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(
            id: 1,
            parent: workspace.floatingWindowsContainer,
            rect: Rect(topLeftX: 100, topLeftY: 100, width: 400, height: 300),
        )
        assertEquals(window.focusWindow(), true)

        await parseCommand("resizeactive 100 -50").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(try await frame(window), [100, 100, 500, 250])

        await parseCommand("resizeactive exact 50% 0").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(try await frame(window), [100, 100, 960, 250])

        // The window can't be shrunk to nothing
        await parseCommand("resizeactive -5000 -5000").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(try await frame(window), [100, 100, 50, 50])

        await parseCommand("resizeactive exact 400 300").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("moveactive 20 -30").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(try await frame(window), [120, 70, 400, 300])

        await parseCommand("moveactive exact 10% 50").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(try await frame(window), [192, 50, 400, 300])

        await parseCommand("centerwindow").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(try await frame(window), [760, 390, 400, 300])
    }

    @Test func testFloatingOnlyCommandsFailForTilingWindows() async {
        let root = Workspace.get(byName: name).rootTilingContainer
        assertEquals(TestWindow.new(id: 1, parent: root).focusWindow(), true)
        assertEquals(await parseCommand("centerwindow").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue != 0, true)
        assertEquals(await parseCommand("moveactive 10 10").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue != 0, true)
        assertEquals(await parseCommand("resizeactive exact 50% 50%").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue != 0, true)
    }

    // MARK: Pseudotiling and smart gaps

    @Test func testPseudotile() async throws {
        let workspace = Workspace.get(byName: name)
        let window1 = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        assertEquals(window1.focusWindow(), true)
        window1.lastFloatingSize = CGSize(width: 400, height: 300)

        await parseCommand("pseudo").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        // The tile is the left half of the 1920x1080 monitor. Height is 1079 because of the 'height - 1' hack of the layout
        assertEquals(try await frame(window1), [280, 389.5, 400, 300])

        // The window never outgrows its tile
        window1.pseudotiledSize = CGSize(width: 5000, height: 300)
        try await workspace.layoutWorkspace()
        assertEquals(try await window1.getAxRect(.nonCancellable)?.width, 960)

        await parseCommand("pseudo").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        assertEquals(try await frame(window1), [0, 0, 960, 1079])
    }

    @Test func testSmartGaps() async throws {
        let workspace = Workspace.get(byName: name)
        let window1 = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        config.gaps = Gaps(inner: .init(vertical: 10, horizontal: 10), outer: .init(left: 20, bottom: 20, top: 20, right: 20), smart: true)

        try await workspace.layoutWorkspace()
        assertEquals(try await frame(window1), [0, 0, 1920, 1079])

        TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        try await workspace.layoutWorkspace()
        // More than one window: the outer gaps are back
        assertEquals(Array(try await frame(window1).prefix(2)), [20, 20])
        assertEquals(try await frame(window1)[3], 1039)

        assertEquals(parseConfig("gaps.smart = true").errors, [])
        assertEquals(parseConfig("gaps.smart = true").config.gaps.smart, true)
    }

    // MARK: Groups

    @Test func testGroups() async {
        let root = Workspace.get(byName: name).rootTilingContainer
        let window1 = TestWindow.new(id: 1, parent: root)
        TestWindow.new(id: 2, parent: root)
        TestWindow.new(id: 3, parent: root)
        assertEquals(window1.focusWindow(), true)

        // 1 and 2 become a new group
        await parseCommand("moveintogroup r").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([.v_accordion([.window(2), .window(1)]), .window(3)]))
        assertEquals(globalFocus.windowOrNil?.windowId, 1)

        await parseCommand("changegroupactive").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 2)
        await parseCommand("changegroupactive b").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 1)

        // 3 joins the existing group
        assertEquals(Window.get(byId: 3)?.focusWindow(), true)
        await parseCommand("moveintogroup l").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([.v_accordion([.window(2), .window(1), .window(3)])]))

        await parseCommand("moveoutofgroup").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([.v_accordion([.window(2), .window(1)]), .window(3)]))
        assertEquals(globalFocus.windowOrNil?.windowId, 3)

        // The window isn't in a group
        assertEquals(await parseCommand("changegroupactive").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue != 0, true)
        assertEquals(await parseCommand("moveoutofgroup").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue != 0, true)

        await parseCommand("togglegroup").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_accordion([.v_accordion([.window(2), .window(1)]), .window(3)]))
        await parseCommand("togglegroup").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([.v_accordion([.window(2), .window(1)]), .window(3)]))
    }

    // MARK: Mouse

    @Test func testMouseDragModifier() {
        assertEquals(parseConfig("").config.mouseDragModifier, nil)
        assertEquals(parseConfig("mouse-drag-modifier = 'off'").config.mouseDragModifier, nil)
        assertEquals(
            parseConfig("mouse-drag-modifier = 'alt'").config.mouseDragModifier,
            MouseDragModifier(flags: CGEventFlags.maskAlternate.rawValue),
        )
        assertEquals(
            parseConfig("mouse-drag-modifier = 'Ctrl-Shift'").config.mouseDragModifier,
            MouseDragModifier(flags: CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue),
        )
        #expect(!parseConfig("mouse-drag-modifier = 'super'").errors.isEmpty)
        #expect(!parseConfig("mouse-drag-modifier = 'alt-'").errors.isEmpty)

        let rect = Rect(topLeftX: 100, topLeftY: 100, width: 400, height: 300)
        // The bottom right corner is dragged
        var resized = resizedRect(rect, dx: 50, dy: -20, resizesLeftEdge: false, resizesTopEdge: false)
        assertEquals([resized.topLeftX, resized.topLeftY, resized.width, resized.height], [100, 100, 450, 280])
        // The top left corner is dragged. The bottom right corner stays where it is
        resized = resizedRect(rect, dx: 50, dy: -20, resizesLeftEdge: true, resizesTopEdge: true)
        assertEquals([resized.topLeftX, resized.topLeftY, resized.width, resized.height], [150, 80, 350, 320])
        // The window can't be shrunk to nothing
        resized = resizedRect(rect, dx: 5000, dy: 5000, resizesLeftEdge: true, resizesTopEdge: true)
        assertEquals([resized.topLeftX, resized.topLeftY, resized.width, resized.height], [450, 350, 50, 50])
    }

    // MARK: Window rules

    @Test func testWindowRules() {
        let result = parseConfig(
            """
            windowrule = [
                'float, class:^(Calculator)$',
                'size 50% 600, class:^(Calculator)$',
                'move 100 100, initialClass:^(Calculator)$',
                'center, title:Preferences, workspace:special:magic',
                'pseudo, initialTitle:Notes',
                'maximize, class:Preview',
            ]
            """,
        )
        assertEquals(result.errors, [])
        assertEquals(result.config.windowRules.count, 6)

        #expect(!parseConfig("windowrule = ['size 50%, class:Foo']").errors.isEmpty)
        #expect(!parseConfig("windowrule = ['size big small, class:Foo']").errors.isEmpty)
        #expect(!parseConfig("windowrule = ['center, floating:1']").errors.isEmpty)
    }
}

/// [x, y, width, height]
@MainActor private func frame(_ window: Window) async throws -> [CGFloat] {
    let rect = try await window.getAxRect(.nonCancellable).orDie()
    return [rect.topLeftX, rect.topLeftY, rect.width, rect.height]
}
