import Foundation
import SQLite3

public struct HistoryEntry: Identifiable {
    public let id: String
    public let title: String
    public let searchText: String
    public let kind: String
    public let source: String
    public let copiedAt: Date
    public let pinned: Bool
    public let byteCount: Int
    public let thumbnail: Data?
}

public enum HistoryError: LocalizedError {
    case database(String)
    case invalidClipboard
    public var errorDescription: String? {
        switch self {
        case .database(let message): return "Clipboard history could not be saved: \(message)"
        case .invalidClipboard: return "This clipboard item is empty or too large."
        }
    }
}

/// Confined to the caller's serial queue. SQLite transactions keep payloads and metadata together.
public final class HistoryStore {
    public static let itemLimit = 25
    public static let byteLimit = 32 * 1_024 * 1_024
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open database"
            if database != nil { sqlite3_close(database) }
            database = nil
            throw HistoryError.database(message)
        }
        sqlite3_busy_timeout(database, 2_000)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try execute("PRAGMA journal_mode = DELETE")
        try execute("PRAGMA secure_delete = ON")
        try execute("""
            CREATE TABLE IF NOT EXISTS history (
                id TEXT PRIMARY KEY, title TEXT NOT NULL, search_text TEXT NOT NULL,
                kind TEXT NOT NULL, source TEXT NOT NULL, copied_at REAL NOT NULL,
                pinned INTEGER NOT NULL DEFAULT 0, byte_count INTEGER NOT NULL,
                payload BLOB NOT NULL, thumbnail BLOB
            )
            """)
    }
    deinit { sqlite3_close(database) }

    public func entries() throws -> [HistoryEntry] {
        let statement = try prepare("SELECT id,title,search_text,kind,source,copied_at,pinned,byte_count,thumbnail FROM history ORDER BY pinned DESC,copied_at DESC,rowid DESC")
        defer { sqlite3_finalize(statement) }
        var values: [HistoryEntry] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            func string(_ column: Int32) -> String {
                let bytes = sqlite3_column_text(statement, column)!
                return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column))), as: UTF8.self)
            }
            values.append(HistoryEntry(
                id: string(0), title: string(1), searchText: string(2), kind: string(3), source: string(4),
                copiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                pinned: sqlite3_column_int(statement, 6) == 1, byteCount: Int(sqlite3_column_int64(statement, 7)),
                thumbnail: blob(statement, column: 8)
            ))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw failure() }
        return values
    }

    @discardableResult
    public func add(_ snapshot: ClipboardSnapshot, source: String, thumbnail: Data? = nil,
                    now: Date = Date()) throws -> Bool {
        guard !snapshot.items.isEmpty, snapshot.items.allSatisfy({ !$0.isEmpty }), snapshot.byteCount > 0,
              snapshot.byteCount <= ClipboardSnapshot.maximumBytes else { throw HistoryError.invalidClipboard }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let payload = try encoder.encode(snapshot)
        let id = snapshot.fingerprint
        try execute("BEGIN IMMEDIATE")
        do {
            let statement = try prepare("""
                INSERT INTO history (id,title,search_text,kind,source,copied_at,byte_count,payload,thumbnail)
                VALUES (?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET copied_at=excluded.copied_at,source=excluded.source
                """)
            defer { sqlite3_finalize(statement) }
            bind(id, to: statement, at: 1)
            bind(snapshot.title, to: statement, at: 2)
            bind(String((snapshot.text ?? snapshot.title).prefix(100_000)), to: statement, at: 3)
            bind(snapshot.kind, to: statement, at: 4)
            bind(source, to: statement, at: 5)
            sqlite3_bind_double(statement, 6, now.timeIntervalSince1970)
            sqlite3_bind_int64(statement, 7, sqlite3_int64(snapshot.byteCount))
            bind(payload, to: statement, at: 8)
            if let thumbnail { bind(thumbnail, to: statement, at: 9) }
            try step(statement)
            let all = try entries()
            var count = all.count
            var bytes = all.reduce(0) { $0 + $1.byteCount }
            for entry in all.reversed() where !entry.pinned && (count > Self.itemLimit || bytes > Self.byteLimit) {
                try delete(id: entry.id)
                count -= 1
                bytes -= entry.byteCount
            }
            // A full set of pins must never evict a favorite to make room for a new copy.
            if count > Self.itemLimit || bytes > Self.byteLimit {
                try execute("ROLLBACK")
                return false
            }
            try execute("COMMIT")
            return try entries().contains { $0.id == id }
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func snapshot(id: String) throws -> ClipboardSnapshot? {
        let statement = try prepare("SELECT payload FROM history WHERE id=?")
        defer { sqlite3_finalize(statement) }
        bind(id, to: statement, at: 1)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW, let data = blob(statement, column: 0) else { throw failure() }
        return try PropertyListDecoder().decode(ClipboardSnapshot.self, from: data)
    }
    public func setPinned(id: String, pinned: Bool) throws {
        let statement = try prepare("UPDATE history SET pinned=? WHERE id=?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, pinned ? 1 : 0)
        bind(id, to: statement, at: 2)
        try step(statement)
    }
    public func delete(id: String) throws {
        let statement = try prepare("DELETE FROM history WHERE id=?")
        defer { sqlite3_finalize(statement) }
        bind(id, to: statement, at: 1)
        try step(statement)
    }
    public func clear(includePinned: Bool = false) throws {
        try execute(includePinned ? "DELETE FROM history" : "DELETE FROM history WHERE pinned=0")
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        return statement
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func step(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }
    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, Int32(value.utf8.count), transient) }
    }
    private func bind(_ value: Data, to statement: OpaquePointer, at index: Int32) {
        _ = value.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), transient) }
    }
    private func blob(_ statement: OpaquePointer, column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
    private func failure() -> HistoryError { .database(String(cString: sqlite3_errmsg(database))) }
}
