public enum SetupStep: Equatable, Sendable {
    case checking, microphone, accessibility, storage, ready
}

/// Setup can be postponed, but an unavailable capability is never presented as
/// ready. Checking the keychain does not itself authorize or prompt for access.
public enum SetupReadiness {
    public static func next(microphone: Bool, accessibility: Bool, requiresExternalAccess: Bool,
                            storageChecked: Bool, storageNeedsAuthorization: Bool) -> SetupStep {
        if !storageChecked { return .checking }
        if !microphone { return .microphone }
        if requiresExternalAccess && !accessibility { return .accessibility }
        if storageNeedsAuthorization { return .storage }
        return .ready
    }
}
