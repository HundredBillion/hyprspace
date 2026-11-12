@testable import AppBundle
import AppKit
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct BorderAndAnimationsTest {
    @Test func testParseConfig() {
        let result = parseConfig(
            """
            border.enabled = false
            border.width = 4
            border.active-color = 'rgba(ff000080)'
            border.rounding = 0
            animations.enabled = false
            animations.duration-ms = 300
            """,
        )
        assertEquals(result.errors, [])
        assertEquals(result.config.border.enabled, false)
        assertEquals(result.config.border.width, 4)
        assertEquals(result.config.border.rounding, 0)
        assertEquals(result.config.border.activeColor, RgbaColor(red: 1, green: 0, blue: 0, alpha: 128 / 255.0))
        assertEquals(result.config.animations, AnimationsConfig(enabled: false, durationMs: 300))
    }

    @Test func testDefaults() {
        let config = parseConfig("").config
        assertEquals(config.border.enabled, true)
        assertEquals(config.border.width, 2)
        assertEquals(config.animations, AnimationsConfig(enabled: true, durationMs: 150))
    }

    @Test func testParseErrors() {
        assertEquals(
            parseConfig("border.active-color = 'blue'").strErrors,
            ["[ERROR] border.active-color: Can't parse color 'blue'. Supported formats: '#rrggbb', '#rrggbbaa', 'rgb(rrggbb)', 'rgba(rrggbbaa)', '0xaarrggbb'"],
        )
        assertEquals(parseConfig("border.width = -1").strErrors, ["[ERROR] border.width: The value must be between 0 and 1000"])
        assertEquals(parseConfig("animations.duration-ms = -5").strErrors, ["[ERROR] animations.duration-ms: The value must be between 0 and 2000"])
        // Used to overflow and crash on the first layout, even with animations disabled
        assertEquals(
            parseConfig("animations.duration-ms = 9223372036854775807").strErrors,
            ["[ERROR] animations.duration-ms: The value must be between 0 and 2000"],
        )
    }

    @Test func testParseColor() {
        assertEquals(RgbaColor.parse("#ff0000"), RgbaColor(red: 1, green: 0, blue: 0, alpha: 1))
        assertEquals(RgbaColor.parse("#00FF0000"), RgbaColor(red: 0, green: 1, blue: 0, alpha: 0))
        assertEquals(RgbaColor.parse("rgb(0000ff)"), RgbaColor(red: 0, green: 0, blue: 1, alpha: 1))
        assertEquals(RgbaColor.parse("rgba(0000ffff)"), RgbaColor(red: 0, green: 0, blue: 1, alpha: 1))
        assertEquals(RgbaColor.parse("0xff00ff00"), RgbaColor(red: 0, green: 1, blue: 0, alpha: 1))
        assertEquals(RgbaColor.parse("#fff"), nil)
        assertEquals(RgbaColor.parse("#ｆｆｆｆｆｆ"), nil) // Fullwidth digits are not hex digits
        assertEquals(RgbaColor.parse("rgb(zzzzzz)"), nil)
        assertEquals(RgbaColor.parse(""), nil)
    }

    @Test func testBorderFrame() {
        // A 400x300 window at the top-left corner of a 1000px tall main monitor
        let frame = borderFrame(
            windowRect: Rect(topLeftX: 100, topLeftY: 50, width: 400, height: 300),
            borderWidth: 2,
            mainMonitorHeight: 1000,
        )
        assertEquals(frame, CGRect(x: 98, y: 648, width: 404, height: 304))
    }

    @Test func testEasingAndInterpolation() {
        assertEquals(easeOutCubic(0), 0)
        assertEquals(easeOutCubic(1), 1)
        assertEquals(easeOutCubic(0.5), 0.875)
        assertEquals(easeOutCubic(2), 1)

        let from = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100)
        let to = Rect(topLeftX: 100, topLeftY: 200, width: 300, height: 500)
        assertEquals(interpolate(from: from, to: to, progress: 0).isAlmostEqual(to: from), true)
        assertEquals(interpolate(from: from, to: to, progress: 1).isAlmostEqual(to: to), true)
        let middle = interpolate(from: from, to: to, progress: 0.5)
        assertEquals(middle.isAlmostEqual(to: Rect(topLeftX: 50, topLeftY: 100, width: 200, height: 300)), true)
    }

    @Test func testHugeDurationDoesNotCrashLayout() async throws {
        setUpWorkspacesForTests()
        config.animations = AnimationsConfig(enabled: false, durationMs: Int.max) // Bypasses the parser on purpose
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        try await workspace.layoutWorkspace()
        #expect(window.lastAppliedLayoutPhysicalRect != nil)
    }

    @Test func testLayoutPlacesWindowsWithoutAnimationInTests() async throws {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: name)
        let window1 = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let window2 = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        try await workspace.layoutWorkspace()
        let rect1 = try await window1.getAxRect(.cancellable).orDie()
        let rect2 = try await window2.getAxRect(.cancellable).orDie()
        assertEquals(rect1.width, rect2.width)
        assertEquals(rect1.topLeftX + rect1.width, rect2.topLeftX)
        assertEquals(window1.lastAppliedLayoutPhysicalRect?.isAlmostEqual(to: rect1), true)
    }
}
