import Testing
@testable import VeylumeCore

struct SetupReadinessTests {
    @Test func setupRequiresEachCapabilityButDoesNotInventAnAccessibilityRequirementForManualUse() {
        func next(_ mic: Bool, _ ax: Bool, _ checked: Bool, _ blocked: Bool, external: Bool = true) -> SetupStep {
            SetupReadiness.next(microphone: mic, accessibility: ax, requiresExternalAccess: external,
                storageChecked: checked, storageNeedsAuthorization: blocked)
        }
        #expect(next(true, true, false, false) == .checking)
        #expect(next(false, false, true, true) == .microphone)
        #expect(next(true, false, true, true) == .accessibility)
        #expect(next(true, true, true, true) == .storage)
        #expect(next(true, true, true, false) == .ready)
        #expect(next(true, false, true, false, external: false) == .ready)
        // An upgrade can lose storage access while retaining both TCC grants.
        #expect(next(true, true, true, true) != .ready)
    }
}
