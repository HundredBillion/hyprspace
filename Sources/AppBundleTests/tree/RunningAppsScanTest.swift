@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct RunningAppsScanTest {
    @Test func testScanOnlyAfterAppEvents() {
        var schedule = RunningAppsScanSchedule()
        #expect(schedule.isScanNeeded) // Startup: the running apps are unknown
        schedule.finish(schedule.start())
        #expect(!schedule.isScanNeeded) // Nothing has launched, terminated or been activated since
        schedule.appsMayHaveChanged()
        #expect(schedule.isScanNeeded)
    }

    @Test func testEventDuringScanIsNotLost() {
        var schedule = RunningAppsScanSchedule()
        let scan = schedule.start()
        schedule.appsMayHaveChanged() // An app launched while the scan was enumerating the apps
        schedule.finish(scan)
        #expect(schedule.isScanNeeded)
    }

    @Test func testCancelledScanIsRepeated() {
        var schedule = RunningAppsScanSchedule()
        _ = schedule.start() // The refresh session was cancelled before the scan finished
        #expect(schedule.isScanNeeded)
    }
}
