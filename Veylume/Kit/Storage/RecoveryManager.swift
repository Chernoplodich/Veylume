import Foundation
import CryptoKit
import VeylumeCore

struct AudioRecoveryMetadata: Codable {
    let id: UUID
    let modelID: String
    let language: String
    let rules: [ReplacementRule]
    let startedAt: Date
    let audioKey: Data
    var chunks: Int
    var samples: Int
}
struct AudioRecoveryEntry: Identifiable { let metadata: AudioRecoveryMetadata; let directory: URL; var id: UUID { metadata.id } }
private struct RecoveryEnvelope: Codable { let expires: Date; let sealed: Data }

final class RecoveryManager: @unchecked Sendable {
    let root: URL
    private let keys: any SecretKeyProvider
    init(root: URL, keys: any SecretKeyProvider) { self.root = root; self.keys = keys }
    func journaler(_ metadata: AudioRecoveryMetadata) throws -> @Sendable (AudioArchive) throws -> Void {
        // One Keychain read per recording, not one IPC round trip per second.
        // The closure and its wrapping key are released when capture stops.
        let key = try keys.key(for: "recovery")
        return { archive in try self.journal(metadata, archive: archive, key: key) }
    }
    private func journal(_ metadata: AudioRecoveryMetadata, archive: AudioArchive, key: SymmetricKey) throws {
        var metadata = metadata; metadata.chunks = archive.chunkCount; metadata.samples = archive.sampleCount
        // Only committed chunks survive a crash; the last pending partial second is
        // deliberately excluded until finish() authenticates it.
        metadata.samples = min(metadata.samples, metadata.chunks * 16000)
        let expires = metadata.startedAt.addingTimeInterval(86400)
        let aad = Data("vey1:audio:\(metadata.id):\(expires.timeIntervalSince1970)".utf8)
        let data = try JSONEncoder().encode(metadata)
        let envelope = RecoveryEnvelope(expires: expires, sealed: try AES.GCM.seal(data, using: key, authenticating: aad).combined!)
        let url = archive.directory.appendingPathComponent("recovery.aead")
        try JSONEncoder().encode(envelope).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func entries(now: Date = Date(), excluding activeID: UUID? = nil) throws -> [AudioRecoveryEntry] {
        let directories = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var result: [AudioRecoveryEntry] = []
        var wrappingKey: SymmetricKey?
        for directory in directories {
            guard let id = UUID(uuidString: directory.lastPathComponent) else { continue }
            // A recovery-disabled/test recording intentionally has no journal.
            // Refreshing Settings must never prune its live encrypted spool.
            guard id != activeID else { continue }
            let url = directory.appendingPathComponent("recovery.aead")
            guard let data = try? Data(contentsOf: url), let envelope = try? JSONDecoder().decode(RecoveryEnvelope.self, from: data) else {
                try? FileManager.default.removeItem(at: directory); continue
            }
            guard envelope.expires > now else { try FileManager.default.removeItem(at: directory); continue }
            let aad = Data("vey1:audio:\(id):\(envelope.expires.timeIntervalSince1970)".utf8)
            if wrappingKey == nil { wrappingKey = try keys.key(for: "recovery") }
            let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.sealed), using: wrappingKey!, authenticating: aad)
            let metadata = try JSONDecoder().decode(AudioRecoveryMetadata.self, from: plain)
            guard metadata.id == id, metadata.audioKey.count == 32,
                  metadata.chunks <= 7201, metadata.samples <= metadata.chunks * 16000 else { throw ValidationError.integrity }
            guard metadata.chunks > 0, metadata.samples > 0 else { try FileManager.default.removeItem(at: directory); continue }
            result.append(AudioRecoveryEntry(metadata: metadata, directory: directory))
        }
        return result.sorted { $0.metadata.startedAt > $1.metadata.startedAt }
    }
    func restore(_ entry: AudioRecoveryEntry) -> AudioArchive {
        let m = entry.metadata
        return AudioArchive(id: m.id, directory: entry.directory, keyData: m.audioKey, chunkCount: m.chunks, sampleCount: m.samples)
    }
    func pruneExpired(now: Date = Date(), excluding activeID: UUID? = nil) throws {
        for directory in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            guard let id = UUID(uuidString: directory.lastPathComponent), id != activeID else { continue }
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("recovery.aead")),
                  let envelope = try? JSONDecoder().decode(RecoveryEnvelope.self, from: data) else {
                // A session-only spool has no persisted key. After a crash it
                // cannot be recovered and must not accumulate on disk.
                try FileManager.default.removeItem(at: directory); continue
            }
            if envelope.expires <= now { try FileManager.default.removeItem(at: directory) }
        }
    }
    func remove(_ entry: AudioRecoveryEntry) throws { try FileManager.default.removeItem(at: entry.directory) }
}
