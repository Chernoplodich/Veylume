import Testing
import Foundation
import Security
import LocalAuthentication
@testable import VeylumeKit
import VeylumeCore

private final class KeychainProbe: KeychainDriver, @unchecked Sendable {
    var allowed = true
    var needsInteraction = false
    var forcedError: OSStatus?
    var copies = 0, additions = 0
    var uiDuringCopy: [Bool] = []
    var contexts: [Bool] = []
    func interactionAllowed() -> (OSStatus, Bool) { (errSecSuccess, allowed) }
    func setInteractionAllowed(_ allowed: Bool) -> OSStatus { self.allowed = allowed; return errSecSuccess }
    func copy(_ query: [String: Any]) -> (OSStatus, Data?) {
        copies += 1; uiDuringCopy.append(allowed)
        contexts.append((query[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed ?? false)
        if let forcedError { return (forcedError, nil) }
        if needsInteraction && !allowed { return (errSecInteractionNotAllowed, nil) }
        return (errSecSuccess, Data(repeating: 11, count: 32))
    }
    func add(_ attributes: [String: Any]) -> OSStatus { additions += 1; return errSecSuccess }
}
struct KeychainTests {
    @Test func freshSetupChecksAllRequiredKeysWithoutCreatingOrPromptingThenConnectsExplicitly() throws {
        let driver = KeychainProbe(); driver.forcedError = errSecItemNotFound
        let keys = KeychainKeys(service: "test-only", driver: driver)
        #expect(throws: ValidationError.keychain) { try keys.verifyRequiredAccess(to: ["recovery", "history"]) }
        #expect(driver.copies == 2); #expect(driver.additions == 0)
        #expect(driver.uiDuringCopy == [false, false]); #expect(driver.allowed)
        try keys.authorizeNeeded(required: ["recovery", "history"])
        #expect(driver.additions == 2); #expect(driver.uiDuringCopy == [false, false, true, true])
        try keys.verifyRequiredAccess(to: ["recovery", "history"])
        #expect(driver.copies == 4)
    }
    @Test func authorizedRelaunchNeedsNoInteractiveAuthorization() throws {
        let driver = KeychainProbe()
        let keys = KeychainKeys(service: "test-only", driver: driver)
        try keys.verifyRequiredAccess(to: ["recovery"])
        try keys.authorizeNeeded()
        #expect(driver.copies == 1); #expect(driver.uiDuringCopy == [false]); #expect(driver.additions == 0)
    }
    @Test func backgroundReadDisablesLegacyUIAndRestoresItsPreviousStateOnFailure() {
        let driver = KeychainProbe(); driver.needsInteraction = true
        let keys = KeychainKeys(service: "test-only", driver: driver)
        #expect(throws: ValidationError.keychain) { try keys.key(for: "recovery") }
        #expect(driver.uiDuringCopy == [false]); #expect(driver.contexts == [true])
        #expect(driver.allowed); #expect(driver.additions == 0)
    }
    @Test func explicitAuthorizationCachesKeyUntilLockAndDoesNotRepeatQueries() throws {
        let driver = KeychainProbe(); driver.needsInteraction = true
        let keys = KeychainKeys(service: "test-only", driver: driver)
        #expect(throws: ValidationError.keychain) { try keys.key(for: "recovery") }
        try keys.authorizeNeeded()
        for _ in 0..<100 { _ = try keys.key(for: "recovery") }
        #expect(driver.copies == 2); #expect(driver.uiDuringCopy == [false, true])
        #expect(driver.contexts == [true, false]); #expect(driver.allowed)
        keys.clearCache()
        #expect(throws: ValidationError.keychain) { try keys.key(for: "recovery") }
        #expect(driver.copies == 3); #expect(driver.uiDuringCopy.last == false)
    }
    @Test func authFailureNeverCreatesOrReplacesAnExistingKey() {
        let driver = KeychainProbe(); driver.allowed = false; driver.forcedError = errSecAuthFailed
        let keys = KeychainKeys(service: "test-only", driver: driver)
        #expect(throws: ValidationError.keychain) { try keys.key(for: "history") }
        #expect(driver.additions == 0); #expect(!driver.allowed)
    }
}
