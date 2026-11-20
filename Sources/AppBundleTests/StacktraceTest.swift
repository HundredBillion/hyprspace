@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct StacktraceTest {
    @Test func testLazyStacktraceIsSymbolicatedOnDemand() {
        let stacktrace = zebraFrame()
        // Only the return addresses are captured. The names are resolved when the stacktrace is printed.
        // The names are mangled, like in Thread.callStackSymbols. A unique word survives the mangling
        #expect(stacktrace.description.contains("zebraFrame"))
        #expect(stacktrace.description.split(separator: "\n").count > 1)
    }

    @inline(never)
    private func zebraFrame() -> LazyStacktrace { LazyStacktrace() }
}
