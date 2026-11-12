import Foundation
import CryptoKit
import CSQLite

public struct StoredText: Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let text: String
    public init(id: UUID, date: Date, text: String) { self.id = id; self.date = date; self.text = text }
}
public enum BlobKind: String, Sendable { case history, recovery, dictionary }
public protocol SecretKeyProvider: Sendable { func key(for purpose: String) throws -> SymmetricKey }
private final class DatabaseConnection: @unchecked Sendable {
    let pointer: OpaquePointer?
    init(_ pointer: OpaquePointer?) { self.pointer = pointer }
    deinit { sqlite3_close(pointer) }
}

/// Metadata is SQLite; content is independently authenticated before any disk write.
/// Schema migration and event idempotency use SQLite transactions, not UI state.
public actor EncryptedStore {
    private let connection: DatabaseConnection
    private var db: OpaquePointer? { connection.pointer }
    private let keys: any SecretKeyProvider
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public init(url: URL, keys: any SecretKeyProvider) throws {
        self.keys = keys
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var connection: OpaquePointer?
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw ValidationError.database }
        self.connection = DatabaseConnection(connection)
        do {
            sqlite3_busy_timeout(connection, 2000)
            try Self.execute(connection, "PRAGMA journal_mode=WAL; PRAGMA secure_delete=ON; PRAGMA foreign_keys=ON;")
            let version = try Self.scalar(connection, "PRAGMA user_version")
            guard version <= 2 else { throw ValidationError.unsupportedSchema }
            if version == 0 {
                try Self.execute(connection, """
                    BEGIN IMMEDIATE;
                    CREATE TABLE blobs (id TEXT NOT NULL, kind TEXT NOT NULL, created REAL NOT NULL, expires REAL, payload BLOB NOT NULL, PRIMARY KEY(id,kind));
                    CREATE TABLE statistics (id TEXT NOT NULL, metric_version INTEGER NOT NULL DEFAULT 1, day TEXT NOT NULL, timezone TEXT NOT NULL, words INTEGER NOT NULL, duration REAL NOT NULL, model TEXT NOT NULL, revision TEXT NOT NULL, PRIMARY KEY(id,metric_version));
                    PRAGMA user_version=2;
                    COMMIT;
                    """)
            }
            if version == 1 {
                try Self.execute(connection, """
                    BEGIN IMMEDIATE;
                    ALTER TABLE statistics RENAME TO statistics_v1;
                    CREATE TABLE statistics (id TEXT NOT NULL, metric_version INTEGER NOT NULL DEFAULT 1, day TEXT NOT NULL, timezone TEXT NOT NULL, words INTEGER NOT NULL, duration REAL NOT NULL, model TEXT NOT NULL, revision TEXT NOT NULL, PRIMARY KEY(id,metric_version));
                    INSERT INTO statistics SELECT * FROM statistics_v1;
                    DROP TABLE statistics_v1;
                    PRAGMA user_version=2;
                    COMMIT;
                    """)
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { throw error }
    }
    private static func execute(_ db: OpaquePointer?, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw ValidationError.database }
    }
    private static func scalar(_ db: OpaquePointer?, _ sql: String) throws -> Int {
        var statement: OpaquePointer?; defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW else { throw ValidationError.database }
        return Int(sqlite3_column_int(statement, 0))
    }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var pointer: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &pointer, nil) == SQLITE_OK, let pointer else { throw ValidationError.database }; return pointer
    }
    private func bind(_ text: String, to statement: OpaquePointer, at position: Int32) { sqlite3_bind_text(statement, position, text, -1, Self.transient) }
    private func step(_ statement: OpaquePointer) throws { guard sqlite3_step(statement) == SQLITE_DONE else { throw ValidationError.database } }
    private func aad(_ id: UUID, _ kind: BlobKind) -> Data { Data("vey1:\(kind.rawValue):\(id.uuidString)".utf8) }
    public func save(id: UUID, kind: BlobKind, data: Data, date: Date = Date(), expires: Date? = nil) throws {
        let key = try keys.key(for: kind == .recovery ? "recovery" : "history")
        let sealed = try AES.GCM.seal(data, using: key, authenticating: aad(id, kind)).combined!
        let s = try statement("INSERT OR REPLACE INTO blobs(id,kind,created,expires,payload) VALUES(?,?,?,?,?)"); defer { sqlite3_finalize(s) }
        bind(id.uuidString, to: s, at: 1); bind(kind.rawValue, to: s, at: 2)
        sqlite3_bind_double(s, 3, date.timeIntervalSince1970)
        if let expires { sqlite3_bind_double(s, 4, expires.timeIntervalSince1970) } else { sqlite3_bind_null(s, 4) }
        _ = sealed.withUnsafeBytes { sqlite3_bind_blob(s, 5, $0.baseAddress, Int32($0.count), Self.transient) }; try step(s)
    }
    public func load(kind: BlobKind, now: Date = Date()) throws -> [(UUID, Date, Data)] {
        try cleanup(now: now)
        let s = try statement("SELECT id,created,payload FROM blobs WHERE kind=? ORDER BY created DESC"); defer { sqlite3_finalize(s) }
        bind(kind.rawValue, to: s, at: 1)
        var rows: [(UUID, Date, Data)] = []
        var key: SymmetricKey?
        while sqlite3_step(s) == SQLITE_ROW {
            guard let id = UUID(uuidString: String(cString: sqlite3_column_text(s, 0))), let pointer = sqlite3_column_blob(s, 2) else { throw ValidationError.database }
            if key == nil { key = try keys.key(for: kind == .recovery ? "recovery" : "history") }
            let encrypted = Data(bytes: pointer, count: Int(sqlite3_column_bytes(s, 2)))
            let data = try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted), using: key!, authenticating: aad(id, kind))
            rows.append((id, Date(timeIntervalSince1970: sqlite3_column_double(s, 1)), data))
        }
        return rows
    }
    public func delete(id: UUID, kind: BlobKind) throws {
        let s = try statement("DELETE FROM blobs WHERE id=? AND kind=?"); defer { sqlite3_finalize(s) }
        bind(id.uuidString, to: s, at: 1); bind(kind.rawValue, to: s, at: 2); try step(s)
    }
    public func deleteAll(kind: BlobKind) throws {
        let s = try statement("DELETE FROM blobs WHERE kind=?"); defer { sqlite3_finalize(s) }; bind(kind.rawValue, to: s, at: 1); try step(s)
        try Self.execute(db, "PRAGMA wal_checkpoint(TRUNCATE)")
    }
    public func cleanup(now: Date = Date()) throws {
        let s = try statement("DELETE FROM blobs WHERE expires IS NOT NULL AND expires<=?"); defer { sqlite3_finalize(s) }
        sqlite3_bind_double(s, 1, now.timeIntervalSince1970); try step(s)
    }
    public func record(_ event: StatisticsEvent) throws {
        let s = try statement("INSERT OR IGNORE INTO statistics(id,day,timezone,words,duration,model,revision) VALUES(?,?,?,?,?,?,?)"); defer { sqlite3_finalize(s) }
        bind(event.id.uuidString, to: s, at: 1); bind(event.day, to: s, at: 2); bind(event.timeZone, to: s, at: 3)
        sqlite3_bind_int64(s, 4, Int64(event.words)); sqlite3_bind_double(s, 5, event.duration)
        bind(event.modelID, to: s, at: 6); bind(event.revision, to: s, at: 7); try step(s)
    }
    public func summary() throws -> StatisticsSummary {
        let s = try statement("SELECT COUNT(*),COALESCE(SUM(words),0),COALESCE(SUM(duration),0),COALESCE(MAX(duration),0) FROM statistics"); defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_ROW else { throw ValidationError.database }
        var summary = StatisticsSummary(); summary.recordings = Int(sqlite3_column_int64(s, 0)); summary.words = Int(sqlite3_column_int64(s, 1)); summary.duration = sqlite3_column_double(s, 2); summary.longest = sqlite3_column_double(s, 3)
        let days = try statement("SELECT day,COUNT(*) FROM statistics GROUP BY day ORDER BY day DESC LIMIT 90"); defer { sqlite3_finalize(days) }
        while sqlite3_step(days) == SQLITE_ROW { summary.days.append((String(cString: sqlite3_column_text(days, 0)), Int(sqlite3_column_int(days, 1)))) }
        return summary
    }
    public func resetStatistics() throws { try Self.execute(db, "DELETE FROM statistics; PRAGMA wal_checkpoint(TRUNCATE)") }
}
