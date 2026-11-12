import Testing
import Foundation
@testable import VeylumeCore

struct StoragePolicyTests {
    @Test func freshDictationNeedsNoPersistentKeyAndKeepsItsInsertionSettings() {
        var preferences = Preferences(); preferences.selectedModel = "parakeet-v3"; preferences.speechLanguage = "ru"
        #expect(!preferences.usesProtectedStorage)
        let recording = preferences.recordingConfiguration(storageAvailable: true)
        #expect(!recording.recoveryEnabled); #expect(!recording.historyEnabled)
        #expect(recording.automaticInsertion); #expect(recording.selectedModel == "parakeet-v3")
        #expect(recording.speechLanguage == "ru")
    }
    @Test func updateCanPauseSavingWithoutLosingTheUsersPreviousChoiceOrBlockingInsertion() {
        var preferences = Preferences(); preferences.storageMode = .protected
        preferences.historyEnabled = true; preferences.recoveryEnabled = true
        preferences.lastAuthorizedStorageBuild = "14"
        let unavailable = preferences.recordingConfiguration(storageAvailable: false)
        #expect(!unavailable.recoveryEnabled); #expect(!unavailable.historyEnabled)
        #expect(unavailable.automaticInsertion)
        #expect(preferences.historyEnabled); #expect(preferences.recoveryEnabled)
        #expect(preferences.lastAuthorizedStorageBuild == "14")
        let reconnected = preferences.recordingConfiguration(storageAvailable: true)
        #expect(reconnected.historyEnabled); #expect(reconnected.recoveryEnabled)
    }
    @Test func oldSettingsRetainProtectedStorageAndExplicitSessionOnlySurvivesRelaunch() throws {
        var original = Preferences(); original.historyEnabled = true; original.onboardingCompleted = true
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "storageMode"); json.removeValue(forKey: "lastAuthorizedStorageBuild")
        let old = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.usesProtectedStorage); #expect(old.historyEnabled); #expect(old.onboardingCompleted)
        original.storageMode = .sessionOnly
        let relaunched = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(original))
        #expect(!relaunched.usesProtectedStorage)
        #expect(relaunched.historyEnabled) // Retained choice; effective recording policy pauses it.
    }
    @Test func optionalStorageNeverBlocksBasicSetupAndRequiredMicrophoneAndAXRemainRequired() {
        func next(_ mic: Bool, _ ax: Bool) -> SetupStep {
            SetupReadiness.next(microphone: mic, accessibility: ax, requiresExternalAccess: true,
                                storageChecked: false, storageNeedsAuthorization: true, requiresProtectedStorage: false)
        }
        #expect(next(true, true) == .ready)
        #expect(next(false, true) == .microphone)
        #expect(next(true, false) == .accessibility)
    }
}
