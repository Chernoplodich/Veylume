import Testing
@testable import VeylumeKit

struct StorageReadinessTests {
    @Test @MainActor func temporaryKeyFailureIsNotLatchedAfterSuccessfulCurrentAccess() async {
        var checks = 0, reads = 0
        let needed = await StorageReadinessProbe.needsAuthorization(requiredKeyAccess: {
            checks += 1; return checks > 1
        }, storedDataAccess: { reads += 1; return true })
        #expect(!needed); #expect(checks == 2); #expect(reads == 1)
    }
    @Test @MainActor func temporaryDataAccessFailureCanRecoverWithoutInteractiveAuthorization() async {
        var reads = 0
        let needed = await StorageReadinessProbe.needsAuthorization(requiredKeyAccess: { true }, storedDataAccess: {
            reads += 1; return reads > 1
        })
        #expect(!needed); #expect(reads == 2)
    }
    @Test @MainActor func realMissingAccessRemainsBlockedAndTheProbeIsBounded() async {
        var checks = 0, reads = 0
        let needed = await StorageReadinessProbe.needsAuthorization(requiredKeyAccess: {
            checks += 1; return false
        }, storedDataAccess: { reads += 1; return true })
        #expect(needed); #expect(checks == 2); #expect(reads == 0)
        let blockedData = await StorageReadinessProbe.needsAuthorization(requiredKeyAccess: { true }, storedDataAccess: { false })
        #expect(blockedData)
    }
    @Test @MainActor func readyStorageDoesNotRepeatWork() async {
        var checks = 0, reads = 0
        let needed = await StorageReadinessProbe.needsAuthorization(requiredKeyAccess: {
            checks += 1; return true
        }, storedDataAccess: { reads += 1; return true })
        #expect(!needed); #expect(checks == 1); #expect(reads == 1)
    }
}
