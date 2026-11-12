import Testing
import Foundation
import CryptoKit
import CSQLite
@testable import VeylumeCore

private struct TestKeys: SecretKeyProvider {
    var unavailable = false
    func key(for purpose: String) throws -> SymmetricKey {
        if unavailable { throw ValidationError.keychain }
        return SymmetricKey(data: Data(repeating: purpose == "history" ? 0x42 : 0x33, count: 32))
    }
}
struct StorageTests {
    private func sql(_ url: URL, _ command: String) throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, command, nil, nil, nil) == SQLITE_OK else { throw ValidationError.database }
    }
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VeylumeTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    @Test func historyEncryptedAndStatisticsIdempotentIndependent() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try EncryptedStore(url: root.appendingPathComponent("data.sqlite"), keys: TestKeys())
        let id = UUID(), phrase = "PRIVATE_FIXTURE_NEVER_PLAINTEXT_5197"
        try await store.save(id: id, kind: .history, data: Data(phrase.utf8))
        let event = StatisticsEvent(id: id, startedAt: Date(), words: 12, duration: 3.5, modelID: "test", revision: "pinned")
        try await store.record(event); try await store.record(event)
        #expect(try await store.summary().recordings == 1)
        #expect(try await store.summary().words == 12)
        #expect(try await store.load(kind: .history).first?.2 == Data(phrase.utf8))
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            #expect(try Data(contentsOf: file).range(of: Data(phrase.utf8)) == nil)
        }
        try await store.deleteAll(kind: .history)
        #expect(try await store.summary().words == 12)
        #expect(try await store.load(kind: .history).isEmpty)
    }
    @Test func expiredRecoveryIsRemovedBeforeRequestingKeys() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("data.sqlite")
        let healthy = try EncryptedStore(url: url, keys: TestKeys())
        try await healthy.save(id: UUID(), kind: .recovery, data: Data("secret".utf8), expires: Date().addingTimeInterval(-1))
        let locked = try EncryptedStore(url: url, keys: TestKeys(unavailable: true))
        #expect(try await locked.load(kind: .recovery).isEmpty)
        await #expect(throws: ValidationError.self) { try await locked.save(id: UUID(), kind: .history, data: Data("no plaintext fallback".utf8)) }
    }
    @Test func encryptedAudioChunksRoundTripAcrossFinalPartialChunk() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let archive = try AudioArchive(id: UUID(), root: root)
        let samples = (0..<34567).map { Float($0 % 127) / 127 }
        try archive.append(Array(samples.prefix(17777))); try archive.append(Array(samples.dropFirst(17777))); try archive.finish()
        #expect(archive.chunkCount == 3)
        #expect(try archive.samples(from: 15997, count: 9000) == Array(samples[15997..<24997]))
        #expect(try archive.samples(from: 0, count: samples.count) == samples)
        let file = archive.directory.appendingPathComponent("000001.aead")
        var corrupted = try Data(contentsOf: file); corrupted[20] ^= 1; try corrupted.write(to: file)
        #expect(throws: (any Error).self) { try archive.samples(from: 16000, count: 10) }
        try archive.remove(); #expect(!FileManager.default.fileExists(atPath: archive.directory.path))
    }
    @Test func migrationPreservesEventsAndEncryptedContent() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("data.sqlite"), id = UUID()
        let first = try EncryptedStore(url: url, keys: TestKeys())
        try await first.save(id: id, kind: .history, data: Data("migration fixture".utf8))
        try await first.record(StatisticsEvent(id: id, startedAt: Date(), words: 7, duration: 4, modelID: "test", revision: "pinned"))
        // Recreate the shipped v1 uniqueness constraint, then reopen through the
        // real migration. Blob ciphertext and existing statistics must survive.
        try sql(url, """
        BEGIN IMMEDIATE;
        ALTER TABLE statistics RENAME TO new_statistics;
        CREATE TABLE statistics (id TEXT PRIMARY KEY, metric_version INTEGER NOT NULL DEFAULT 1, day TEXT NOT NULL, timezone TEXT NOT NULL, words INTEGER NOT NULL, duration REAL NOT NULL, model TEXT NOT NULL, revision TEXT NOT NULL);
        INSERT INTO statistics SELECT * FROM new_statistics;
        DROP TABLE new_statistics;
        PRAGMA user_version=1;
        COMMIT;
        """)
        let migrated = try EncryptedStore(url: url, keys: TestKeys())
        #expect(try await migrated.summary().words == 7)
        #expect(try await migrated.load(kind: .history).first?.2 == Data("migration fixture".utf8))
        try await migrated.record(StatisticsEvent(id: id, startedAt: Date(), words: 7, duration: 4, modelID: "test", revision: "pinned"))
        #expect(try await migrated.summary().recordings == 1)
        try sql(url, "PRAGMA user_version=99")
        #expect(throws: ValidationError.unsupportedSchema) { try EncryptedStore(url: url, keys: TestKeys()) }
    }
    @Test func interruptedCaptureRecoversOnlyCommittedChunksAndAuthenticatesIdentity() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), original = try AudioArchive(id: id, root: root)
        let samples = (0..<17000).map { Float($0 % 53) / 53 }
        try original.append(samples)
        // Simulate process death without finish(): the RAM tail was never
        // journaled and must not be invented by a recovered reader.
        let recovered = AudioArchive(id: id, directory: original.directory, keyData: original.keyData, chunkCount: 1, sampleCount: 16000)
        #expect(try recovered.samples(from: 0, count: 17000) == Array(samples.prefix(16000)))
        let wrongIdentity = AudioArchive(id: UUID(), directory: original.directory, keyData: original.keyData, chunkCount: 1, sampleCount: 16000)
        #expect(throws: (any Error).self) { try wrongIdentity.samples(from: 0, count: 1) }
    }
}
