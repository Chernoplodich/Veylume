public enum SetupStep: Equatable, Sendable {
    case checking, microphone, accessibility, storage, ready
}

/// Required capabilities must be granted. Optional encrypted storage can pause
/// independently of basic dictation. A check never authorizes or prompts.
public enum SetupReadiness {
    public static func next(microphone: Bool, accessibility: Bool, requiresExternalAccess: Bool,
                            storageChecked: Bool, storageNeedsAuthorization: Bool,
                            requiresProtectedStorage: Bool = true) -> SetupStep {
        if requiresProtectedStorage && !storageChecked { return .checking }
        if !microphone { return .microphone }
        if requiresExternalAccess && !accessibility { return .accessibility }
        if requiresProtectedStorage && storageNeedsAuthorization { return .storage }
        return .ready
    }
}
