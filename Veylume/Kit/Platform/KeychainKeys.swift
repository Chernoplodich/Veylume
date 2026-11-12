import Foundation
import Security
import CryptoKit
import LocalAuthentication
import VeylumeCore

protocol KeychainDriver: Sendable {
    func interactionAllowed() -> (OSStatus, Bool)
    func setInteractionAllowed(_ allowed: Bool) -> OSStatus
    func copy(_ query: [String: Any]) -> (OSStatus, Data?)
    func add(_ attributes: [String: Any]) -> OSStatus
}
private struct SystemKeychainDriver: KeychainDriver {
    func interactionAllowed() -> (OSStatus, Bool) {
        var allowed = DarwinBoolean(false)
        let status = SecKeychainGetUserInteractionAllowed(&allowed)
        return (status, allowed.boolValue)
    }
    func setInteractionAllowed(_ allowed: Bool) -> OSStatus { SecKeychainSetUserInteractionAllowed(allowed) }
    func copy(_ query: [String: Any]) -> (OSStatus, Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }
    func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
}

/// Noninteractive by default, including the legacy login keychain. LAContext's
/// interactionNotAllowed does NOT suppress that keychain's ACL dialogs (Apple
/// SDK SecItem.h, FB16959400). Scope the legacy UI flag, restore it, serialize
/// our calls, and never replace an inaccessible existing key with a new one.
final class KeychainKeys: SecretKeyProvider, @unchecked Sendable {
    private static let gate = NSRecursiveLock()
    private let service: String
    private let driver: any KeychainDriver
    private var cache: [String: SymmetricKey] = [:]
    private var blocked: Set<String> = []
    init(service: String = (Bundle.main.bundleIdentifier ?? "local.Veylume.dev") + ".keys", driver: (any KeychainDriver)? = nil) {
        self.service = service; self.driver = driver ?? SystemKeychainDriver()
    }
    func key(for purpose: String) throws -> SymmetricKey { try access(purpose, interactive: false) }
    func verifyExistingAccess(to purpose: String) throws { _ = try access(purpose, interactive: false, createIfMissing: false) }
    func verifyRequiredAccess(to purposes: [String]) throws {
        var unavailable = false
        for purpose in Set(purposes).sorted() {
            do { try verifyExistingAccess(to: purpose) } catch { unavailable = true }
        }
        if unavailable { throw ValidationError.keychain }
    }
    func authorizeNeeded(required: [String] = []) throws {
        Self.gate.lock(); let purposes = blocked.union(required).sorted(); Self.gate.unlock()
        for purpose in purposes { _ = try access(purpose, interactive: true) }
    }
    func clearCache() { Self.gate.lock(); defer { Self.gate.unlock() }; cache.removeAll() }
    private func access(_ purpose: String, interactive: Bool, createIfMissing: Bool = true) throws -> SymmetricKey {
        Self.gate.lock(); defer { Self.gate.unlock() }
        if let key = cache[purpose] { return key }
        let (status, previousUI) = driver.interactionAllowed()
        guard status == errSecSuccess, driver.setInteractionAllowed(interactive) == errSecSuccess else { blocked.insert(purpose); throw ValidationError.keychain }
        defer { _ = driver.setInteractionAllowed(previousUI) }
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: purpose]
        var query = base; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext(); context.interactionNotAllowed = !interactive
        query[kSecUseAuthenticationContext as String] = context
        func accepted(_ data: Data?) throws -> SymmetricKey {
            guard let data, data.count == 32 else { throw ValidationError.keychain }
            let key = SymmetricKey(data: data); cache[purpose] = key; blocked.remove(purpose); return key
        }
        let (found, data) = driver.copy(query)
        if found == errSecSuccess { return try accepted(data) }
        guard found == errSecItemNotFound else { blocked.insert(purpose); throw ValidationError.keychain }
        guard createIfMissing else { blocked.insert(purpose); throw ValidationError.keychain }
        let key = SymmetricKey(size: .bits256); var add = base
        add[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = driver.add(add)
        if added == errSecDuplicateItem {
            let (status, existing) = driver.copy(query)
            guard status == errSecSuccess else { blocked.insert(purpose); throw ValidationError.keychain }
            return try accepted(existing)
        }
        guard added == errSecSuccess else { blocked.insert(purpose); throw ValidationError.keychain }
        cache[purpose] = key; blocked.remove(purpose); return key
    }
}
