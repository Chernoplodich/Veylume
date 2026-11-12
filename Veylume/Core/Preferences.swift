import Foundation

public enum Theme: String, Codable, CaseIterable, Sendable { case system, light, dark }
public enum MaterialStyle: String, Codable, CaseIterable, Sendable { case glass, frosted }
public enum IndicatorStyle: String, Codable, CaseIterable, Sendable { case auto, mini, notch, island }
public enum IndicatorPosition: String, Codable, CaseIterable, Sendable { case top, bottom }
public enum BootstrapState: String, Codable, Sendable { case pending, running, paused, cancelled, completed, removed }
public struct Preferences: Codable, Sendable {
    public var version = 1
    public var mode: RecordingMode = .hold
    public var shortcut: Shortcut?
    public var shortcutSchema: Int? = 2
    public var holdShortcut: Shortcut?
    public var toggleShortcut: Shortcut?
    public var hasShortcuts: Bool { holdShortcut != nil || toggleShortcut != nil }
    public var preferredShortcut: Shortcut? { holdShortcut ?? toggleShortcut }
    public mutating func migrateSettings() {
        if shortcutSchema != 2 {
            if mode == .hold { holdShortcut = shortcut } else { toggleShortcut = shortcut }
            shortcutSchema = 2
        }
        // Frosted remains decodable for old settings; the product now uses Glass.
        material = .glass
        if indicator == .auto || indicator == .island { indicator = .notch }
        recordingLimitMinutes = min(120, max(5, recordingLimitMinutes))
    }
    public var shortcutsPaused = false
    public var selectedModel: String?
    public var modelSelectionGeneration: UInt64 = 0
    public var speechLanguage = "auto"
    public var uiLanguage = "system"
    public var theme: Theme = .system
    public var material: MaterialStyle = .glass
    public var indicator: IndicatorStyle = .notch
    // Optional so existing settings decode without losing shortcuts/models.
    public var indicatorPosition: IndicatorPosition?
    public var resolvedIndicatorPosition: IndicatorPosition { indicatorPosition ?? .top }
    public var screenID: UInt32?
    public var microphoneUID: String?
    public var automaticInsertion = true
    public var recoveryEnabled = true
    public var historyEnabled = false
    public var historyDays = 30
    public var recordingLimitMinutes = 30
    public var soundVolume: Float = 0.35
    public var soundsEnabled = true
    public var keepModelWarm = false
    public var automaticallyCheckUpdates = true
    public var onboardingStep = 0
    public var onboardingCompleted = false
    public var bootstrap: BootstrapState = .pending
    public init() {}
    public mutating func selectModel(_ id: String?) { selectedModel = id; modelSelectionGeneration &+= 1 }
    public mutating func completeBootstrap(selectionGeneration: UInt64) {
        bootstrap = .completed
        if modelSelectionGeneration == selectionGeneration, selectedModel == nil { selectedModel = "parakeet-v3" }
    }
}

public struct ModelArtifact: Codable, Sendable {
    public let path: String
    public let url: URL
    public let bytes: Int64
    public let sha256: String
    public init(path: String, url: URL, bytes: Int64, sha256: String) { self.path = path; self.url = url; self.bytes = bytes; self.sha256 = sha256 }
    public func validate(hosts: [String]) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !path.contains(":"), url.scheme == "https", url.user == nil, url.password == nil,
              hosts.contains(url.host ?? ""), bytes > 0,
              sha256.count == 64, sha256.allSatisfy({ $0.isHexDigit }) else { throw ValidationError.unsafeArtifact }
    }
}
public struct ModelManifest: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let publisher: String
    public let engine: String
    public let revision: String
    public let repository: String
    public let license: String
    public let licenseURL: URL
    public let modelCardURL: URL
    public let minimumOS: Int
    public let recommendedMemoryGB: Int
    public let languages: [String]
    public let supportsAutoLanguage: Bool
    public let supportsLanguageHint: Bool
    public let speed: Int
    public let accuracy: Int
    public let ratingRevision: Int
    public let allowedHosts: [String]
    public let artifacts: [ModelArtifact]
    public var downloadBytes: Int64 { artifacts.reduce(0) { $0 + $1.bytes } }
    public func validate() throws {
        guard !artifacts.isEmpty, Set(artifacts.map(\.path)).count == artifacts.count,
              revision.count == 40, revision.allSatisfy({ $0.isHexDigit }),
              (1...5).contains(speed), (1...5).contains(accuracy) else { throw ValidationError.integrity }
        for file in artifacts { try file.validate(hosts: allowedHosts) }
    }
    public func validate(language: String) throws {
        if language == "auto" { guard supportsAutoLanguage else { throw ValidationError.language } }
        else { guard supportsLanguageHint, languages.contains(language) else { throw ValidationError.language } }
    }
}

public enum InsertionOutcome: String, Codable, Sendable { case verifiedInserted, dispatchedUnverified, manualRequired, cancelledBeforeCommit }
public struct StatisticsEvent: Codable, Sendable {
    public let id: UUID
    public let day: String
    public let timeZone: String
    public let words: Int
    public let duration: Double
    public let modelID: String
    public let revision: String
    public init(id: UUID, startedAt: Date, words: Int, duration: Double, modelID: String, revision: String, timeZone: TimeZone = .current) {
        self.id = id; self.words = words; self.duration = duration; self.modelID = modelID; self.revision = revision; self.timeZone = timeZone.identifier
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = timeZone
        self.day = formatter.string(from: startedAt)
    }
}
public struct StatisticsSummary: Sendable {
    public var recordings = 0, words = 0
    public var duration = 0.0, longest = 0.0
    public var days: [(String, Int)] = []
    public init() {}
}
