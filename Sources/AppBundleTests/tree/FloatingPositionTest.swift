@testable import AppBundle
import AppKit
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct FloatingPositionTest {
    @Test func testTopLeftCornerKeepsTheRelativePosition() {
        let monitor = Rect(topLeftX: 1000, topLeftY: 0, width: 2000, height: 1000)
        let size = CGSize(width: 400, height: 300)
        // A quarter of the way across and down the other monitor
        assertEquals(Window.topLeftCorner(atProportion: CGPoint(x: 0.25, y: 0.25), in: monitor, windowSize: size), CGPoint(x: 1500, y: 250))
        // The window would stick out of the right and the bottom edges. It's moved back inside
        assertEquals(Window.topLeftCorner(atProportion: CGPoint(x: 0.9, y: 0.9), in: monitor, windowSize: size), CGPoint(x: 2600, y: 700))
        // The window is to the left of the monitor
        assertEquals(Window.topLeftCorner(atProportion: CGPoint(x: -0.5, y: 0), in: monitor, windowSize: size), CGPoint(x: 1000, y: 0))
        // The window is bigger than the monitor. It's aligned with the top-left corner
        assertEquals(
            Window.topLeftCorner(atProportion: CGPoint(x: 0.5, y: 0.5), in: monitor, windowSize: CGSize(width: 3000, height: 2000)),
            CGPoint(x: 1000, y: 0),
        )
    }
}
