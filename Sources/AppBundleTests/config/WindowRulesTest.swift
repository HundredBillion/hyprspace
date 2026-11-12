@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct WindowRulesTest {
    init() { setUpWorkspacesForTests() }

    @Test func testParse() {
        let result = parseConfig(
            """
            windowrule = [
                'float, class:^(Calculator)$',
                'workspace 3 silent, class:Slack, title:.*Huddle.*',
                'pin, title:Picture in Picture',
            ]
            """,
        )
        assertEquals(result.errors, [])
        // 'pin' expands to two commands: make the window floating, then pin it
        assertEquals(result.config.windowRules.count, 4)
        assertEquals(result.config.windowRules.allSatisfy(\.checkFurtherCallbacks), true)
    }

    @Test func testRegexMayContainCommas() {
        assertEquals(splitWindowRule("float, title:a{1,3}"), ["float", "title:a{1,3}"])
        assertEquals(splitWindowRule("float, class:Foo, Inc, title:Bar"), ["float", "class:Foo, Inc", "title:Bar"])
        assertEquals(splitWindowRule("workspace 3 silent,class:Slack"), ["workspace 3 silent", "class:Slack"])
        assertEquals(splitWindowRule("float"), ["float"])

        let result = parseConfig("windowrule = ['float, title:a{1,3}', 'float, class:Foo, Inc']")
        assertEquals(result.errors, [])
        assertEquals(result.config.windowRules.count, 2)
    }

    @Test func testRegexCantEscapeTheFullMatch() {
        // 'a)|(b' is not a valid regex on its own. It must not be accepted as '^(?:a)|(b)$'
        #expect(!parseConfig("windowrule = ['float, class:a)|(b']").errors.isEmpty)
    }

    @Test func testParseErrors() {
        assertEquals(
            parseConfig("windowrule = ['float']").strErrors,
            ["[ERROR] windowrule[0]: Can't parse window rule 'float'. Expected format: 'RULE, MATCHER[, MATCHER]...'"],
        )
        assertEquals(
            parseConfig("windowrule = ['explode, class:Foo']").strErrors,
            ["[ERROR] windowrule[0]: Can't parse window rule 'explode'. Supported rules: float, tile, pin, fullscreen, workspace <name> [silent]"],
        )
        assertEquals(
            parseConfig("windowrule = ['float, pid:42']").strErrors,
            ["[ERROR] windowrule[0]: Can't parse window rule matcher 'pid:42'. Supported matchers: 'class:<regex>', 'title:<regex>'"],
        )
    }

    @Test func testFloatRuleMatchesByClass() async {
        config.windowRules = parseConfig("windowrule = ['float, class:.*test-app']").config.windowRules
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(window.focusWindow(), true)

        await runOnWindowDetected(ifConventional: window)
        assertEquals(window.isFloating, true)
    }

    @Test func testClassMustMatchTheFullString() async {
        config.windowRules = parseConfig("windowrule = ['float, class:test']").config.windowRules
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(window.focusWindow(), true)

        await runOnWindowDetected(ifConventional: window)
        assertEquals(window.isFloating, false)
    }

    @Test func testWorkspaceAndPinRules() async {
        config.windowRules = parseConfig(
            """
            windowrule = [
                'workspace 7 silent, title:TestWindow.*',
                'pin, title:TestWindow.*',
            ]
            """,
        ).config.windowRules
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(window.focusWindow(), true)

        await runOnWindowDetected(ifConventional: window)
        assertEquals(window.nodeWorkspace?.name, "7")
        assertEquals(window.isFloating, true)
        assertEquals(window.isPinned, true)
    }
}
