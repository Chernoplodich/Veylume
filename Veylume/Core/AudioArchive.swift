import Foundation
import CryptoKit

/// Each authenticated file is at most one second of mono 16 kHz PCM. No open PCM
/// is ever spooled to /tmp. The random session key is wrapped by the recovery key
/// only when recovery was explicitly enabled in this session's snapshot.
public final class AudioArchive: @unchecked Sendable {
    public let id: UUID
    public let directory: URL
    private let key: SymmetricKey
    public private(set) var sampleCount = 0
    public private(set) var chunkCount = 0
    private var pending: [Float] = []
    public init(id: UUID, root: URL, key: SymmetricKey = SymmetricKey(size: .bits256)) throws {
        self.id = id; self.key = key; directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var excluded = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true; try excluded.setResourceValues(values)
        pending.reserveCapacity(32000)
    }
    public init(id: UUID, directory: URL, keyData: Data, chunkCount: Int, sampleCount: Int) {
        self.id = id; self.directory = directory; key = SymmetricKey(data: keyData); self.chunkCount = chunkCount; self.sampleCount = sampleCount
    }
    public var keyData: Data { key.withUnsafeBytes { Data($0) } }
    public var duration: Double { Double(sampleCount) / 16000 }
    public func append(_ samples: [Float]) throws {
        pending.append(contentsOf: samples); sampleCount += samples.count
        while pending.count >= 16000 { try write(Array(pending.prefix(16000))); pending.removeFirst(16000) }
    }
    public func finish() throws { if !pending.isEmpty { try write(pending); pending.removeAll(keepingCapacity: false) } }
    private func associated(_ index: Int) -> Data { Data("\(id.uuidString):pcm16k:\(index)".utf8) }
    private func write(_ samples: [Float]) throws {
        let plain = samples.withUnsafeBytes { Data($0) }
        let sealed = try AES.GCM.seal(plain, using: key, authenticating: associated(chunkCount)).combined!
        let url = directory.appendingPathComponent(String(format: "%06d.aead", chunkCount))
        try sealed.write(to: url, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path); chunkCount += 1
    }
    public func samples(from start: Int, count: Int) throws -> [Float] {
        guard start >= 0, count >= 0, count <= 16000 * 180 else { throw ValidationError.integrity }
        let end = min(sampleCount, start + count); guard start < end else { return [] }
        var result: [Float] = []; result.reserveCapacity(end - start)
        for index in (start / 16000)...((end - 1) / 16000) {
            let file = directory.appendingPathComponent(String(format: "%06d.aead", index))
            let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: Data(contentsOf: file)), using: key, authenticating: associated(index))
            let values = plain.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            let lower = max(0, start - index * 16000), upper = min(values.count, end - index * 16000)
            guard lower <= upper else { throw ValidationError.integrity }; result.append(contentsOf: values[lower..<upper])
        }
        return result
    }
    public func remove() throws { pending.removeAll(); if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) } }
}
