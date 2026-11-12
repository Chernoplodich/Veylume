/// A bounded, noninteractive check. A successful current probe replaces an old
/// failure; it never turns a historical failure into a permanent authorization
/// requirement. No keys are created and no authorization is requested here.
@MainActor enum StorageReadinessProbe {
    static func needsAuthorization(requiredKeyAccess: () async -> Bool,
                                   storedDataAccess: () async -> Bool) async -> Bool {
        for _ in 0..<2 {
            if await requiredKeyAccess(), await storedDataAccess() { return false }
        }
        return true
    }
}
