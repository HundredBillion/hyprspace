@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct ActivationPolicyQueryTest {
    @Test func testOnlyUnknownProcessesAreAsked() {
        // Every activationPolicy call is a request to LaunchServices. There are well over a hundred processes
        let asked = processesToAskForActivationPolicy(
            running: [10, 20, 30, 40],
            registered: [10], // Already managed: nothing to ask
            knownNonRegular: [20], // Answered "not a regular app" before
        )
        assertEquals(asked, [30, 40])
    }

    @Test func testForgottenProcessIsAskedAgain() {
        resetKnownNonRegularProcesses()
        rememberNonRegularProcess(20)
        assertEquals(processesToAskForActivationPolicy(running: [20], registered: [], knownNonRegular: knownNonRegularProcesses), [])
        // The process was activated (or relaunched with the same pid): it may be a regular app now
        forgetActivationPolicy(of: 20)
        assertEquals(processesToAskForActivationPolicy(running: [20], registered: [], knownNonRegular: knownNonRegularProcesses), [20])
    }
}
