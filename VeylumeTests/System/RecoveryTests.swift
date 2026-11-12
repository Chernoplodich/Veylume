import Testing
import Foundation
import CryptoKit
@testable import VeylumeKit
import VeylumeCore

private final class CountingRecoveryKeys: SecretKeyProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var reads: Int { lock.lock(); defer { lock.unlock() }; return count }
    func key(for purpose: String) -> SymmetricKey {
        lock.lock(); count += 1; lock.unlock()
        return SymmetricKey(data: Data(repeating: 7, count: 32))
    }
}
struct RecoveryTests {
    @Test func normalUnverifiedDispatchDoesNotGrowRecoveryOrReadItsKeyAndOldResultsSurvive() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VeylumeResultPolicy-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = CountingRecoveryKeys(), store = try EncryptedStore(url: root.appendingPathComponent("store.sqlite"), keys: keys)
        let old = ResultEntry(id: UUID(), date: Date(), text: "Old pending fixture", outcome: .manualRequired, incomplete: false)
        try await old.persistRecovery(in: store, enabled: true)
        let readsBeforeDispatch = keys.reads
        let dispatched = ResultEntry(id: UUID(), date: Date(), text: "RAM-only fixture", outcome: .dispatchedUnverified, incomplete: false)
        try await dispatched.persistRecovery(in: store, enabled: true)
        #expect(keys.reads == readsBeforeDispatch)
        let manual = ResultEntry(id: UUID(), date: Date(), text: "New manual fixture", outcome: .manualRequired, incomplete: false)
        let partial = ResultEntry(id: UUID(), date: Date(), text: "Incomplete fixture", outcome: .manualRequired, incomplete: true)
        try await manual.persistRecovery(in: store, enabled: true)
        try await partial.persistRecovery(in: store, enabled: true)
        let recovered = try await store.load(kind: .recovery)
        #expect(Set(recovered.map { $0.0 }) == Set([old.id, manual.id, partial.id]))
        #expect(!recovered.contains(where: { $0.0 == dispatched.id }))
    }
    @Test func previousResultWithoutDiagnosticReasonStillRecovers() throws {
        let id = UUID()
        let old = try JSONSerialization.data(withJSONObject: ["id": id.uuidString, "date": 0, "text": "Recovery fixture", "outcome": "manualRequired", "incomplete": false])
        let entry = try JSONDecoder().decode(ResultEntry.self, from: old)
        #expect(entry.id == id); #expect(entry.text == "Recovery fixture")
        #expect(entry.manualReason == nil); #expect(entry.outcome == .manualRequired)
    }
    @Test func settingsRefreshNeverPrunesActiveSpoolWithoutRecoveryJournal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VeylumeRecovery-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = try AudioArchive(id: UUID(), root: root), keys = CountingRecoveryKeys()
        try archive.append([Float](repeating: 0.25, count: 16000))
        let manager = RecoveryManager(root: root, keys: keys)
        #expect(try manager.entries(excluding: archive.id).isEmpty)
        try manager.pruneExpired(excluding: archive.id)
        #expect(FileManager.default.fileExists(atPath: archive.directory.path))
        #expect(keys.reads == 0)
        try manager.pruneExpired()
        #expect(try manager.entries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: archive.directory.path))
    }
    @Test func recoveryJournalReadsKeyOncePerCaptureAndRestoresCommittedAudio() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VeylumeRecovery-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = try AudioArchive(id: UUID(), root: root), keys = CountingRecoveryKeys()
        let manager = RecoveryManager(root: root, keys: keys)
        let metadata = AudioRecoveryMetadata(id: archive.id, modelID: "parakeet-v3", language: "auto", rules: [], startedAt: Date(), audioKey: archive.keyData, chunks: 0, samples: 0)
        let journal = try manager.journaler(metadata)
        for _ in 0..<4 { try archive.append([Float](repeating: 0.25, count: 16000)); try journal(archive) }
        #expect(keys.reads == 1)
        let entry = try #require(manager.entries().first)
        #expect(keys.reads == 2); #expect(entry.metadata.samples == 64000)
        #expect(try manager.restore(entry).samples(from: 63000, count: 1000) == [Float](repeating: 0.25, count: 1000))
        #expect(try manager.entries(now: Date().addingTimeInterval(86401)).isEmpty)
        #expect(keys.reads == 2) // expiry is applied before any Keychain request
    }
}
