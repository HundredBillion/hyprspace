@testable import AppBundle
import Common
import Foundation
import Testing

@MainActor
@Suite(.serializedGlobally)
struct RegexTimeoutTest {
    init() {
        setUpWorkspacesForTests()
        resetTimedOutRegexes()
    }

    /// Catastrophic backtracking: the number of steps doubles with every extra 'a'
    private let evilRegex = CaseInsensitiveRegex.new("^(a+)+$").getOrDie()
    private let evilInput = String(repeating: "a", count: 60) + "!"

    @Test func testOrdinaryRegex() async {
        let regex = CaseInsensitiveRegex.new("^(?:.*huddle.*)$").getOrDie()
        assertEquals(await "Slack Huddle with Bob".contains(caseInsensitiveRegex: regex, timeoutMs: 1000), true)
        assertEquals(await "Slack".contains(caseInsensitiveRegex: regex, timeoutMs: 1000), false)
        assertEquals(await containsWithTimeout("Slack Huddle with Bob", regex), true)
    }

    @Test func testPathologicalRegexGivesUp() async {
        let start = Date.now
        assertEquals(await evilInput.contains(caseInsensitiveRegex: evilRegex, timeoutMs: 100), nil)
        #expect(start.distance(to: .now) < 5) // Without the timeout it would take years
    }

    @Test func testPathologicalRegexIsIgnoredAfterTheFirstTimeout() async {
        assertEquals(await containsWithTimeout(evilInput, evilRegex), false)
        // The second attempt must not even start the regex. It also must not match inputs that are trivially fine
        let start = Date.now
        assertEquals(await containsWithTimeout("aaa", evilRegex), false)
        #expect(start.distance(to: .now) < 0.1)

        resetTimedOutRegexes() // That's what 'reload-config' does
        assertEquals(await containsWithTimeout("aaa", evilRegex), true)
    }

    @Test func testWindowRuleWithPathologicalRegexDoesNotHang() async {
        // The title of TestWindow is 'TestWindow(1)'. The app name is the long bundle ID of the test app
        config.windowRules = parseConfig("windowrule = ['float, class:(.+)+!']").config.windowRules
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: name).rootTilingContainer)
        assertEquals(window.focusWindow(), true)

        let start = Date.now
        await runOnWindowDetected(ifConventional: window)
        #expect(start.distance(to: .now) < 5)
        assertEquals(window.isFloating, false)
    }

    @Test func testSlowAnimationDetection() {
        assertEquals(isAnimationTooSlow(sentFrames: 8, droppedFrames: 0), false)
        assertEquals(isAnimationTooSlow(sentFrames: 5, droppedFrames: 3), false)
        assertEquals(isAnimationTooSlow(sentFrames: 2, droppedFrames: 6), true)
        assertEquals(isAnimationTooSlow(sentFrames: 1, droppedFrames: 2), false) // Too short to judge
    }
}
