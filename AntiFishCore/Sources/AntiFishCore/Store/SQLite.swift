import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLiteError: Error, Equatable {
    case notFound(String)
    case cannotOpen(String)
    case prepare(String)
    case step(String)
}

/// A value bound to a statement parameter.
public enum SQLiteValue: Equatable, Sendable {
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
    case null
}

/// One result row, addressed by column name. Reads of a missing column or a NULL return nil.
public struct SQLiteRow: Sendable {
    private let values: [String: SQLiteValue]
    /// Column names in result order, so scalar queries can address the only column.
    public let columnNames: [String]

    init(values: [String: SQLiteValue], columnNames: [String]) {
        self.values = values
        self.columnNames = columnNames
    }

    public func value(_ column: String) -> SQLiteValue? {
        guard let v = values[column], v != .null else { return nil }
        return v
    }

    /// Integer read that also accepts a REAL column — WhatsApp stores timestamps both ways.
    public func int(_ column: String) -> Int64? {
        switch value(column) {
        case .int(let i): return i
        case .double(let d): return Int64(d)
        case .text(let s): return Int64(s)
        default: return nil
        }
    }

    public func double(_ column: String) -> Double? {
        switch value(column) {
        case .double(let d): return d
        case .int(let i): return Double(i)
        case .text(let s): return Double(s)
        default: return nil
        }
    }

    public func string(_ column: String) -> String? {
        if case .text(let s) = value(column) { return s }
        return nil
    }

    public func data(_ column: String) -> Data? {
        if case .blob(let d) = value(column) { return d }
        return nil
    }

    public func bool(_ column: String) -> Bool? {
        int(column).map { $0 != 0 }
    }
}

/// Thin wrapper over the system SQLite3 library.
///
/// Serialised behind a lock so one instance can be shared across tasks. WhatsApp's databases are
/// opened read-only while WhatsApp itself is writing; SQLite's WAL mode makes that safe and the
/// reader still sees rows that are only in the write-ahead log.
public final class SQLiteDatabase: @unchecked Sendable {
    private let handle: OpaquePointer
    private let lock = NSLock()
    public let path: String

    public init(url: URL, readOnly: Bool, busyTimeoutSeconds: Double = 2) throws {
        let path = url.path
        if readOnly {
            guard FileManager.default.fileExists(atPath: path) else { throw SQLiteError.notFound(path) }
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        }
        var handle: OpaquePointer?
        let flags = (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
            | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let opened = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if handle != nil { sqlite3_close_v2(handle) }
            throw SQLiteError.cannotOpen("\(url.lastPathComponent): \(message)")
        }
        self.handle = opened
        self.path = path
        sqlite3_busy_timeout(opened, Int32(busyTimeoutSeconds * 1000))
    }

    /// Private in-memory database. Used by tests and by callers that want a scratch store.
    public static func inMemory() throws -> SQLiteDatabase {
        try SQLiteDatabase(memoryHandleFor: ":memory:")
    }

    private init(memoryHandleFor path: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let opened = handle else {
            throw SQLiteError.cannotOpen(path)
        }
        self.handle = opened
        self.path = path
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    // MARK: Statements

    private func withStatement<T>(_ sql: String, bind: (OpaquePointer) -> Void,
                                  _ body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let prepared = statement else {
            let message = String(cString: sqlite3_errmsg(handle))
            if statement != nil { sqlite3_finalize(statement) }
            throw SQLiteError.prepare(message)
        }
        defer { sqlite3_finalize(prepared) }
        bind(prepared)
        return try body(prepared)
    }

    private static func bind(_ value: SQLiteValue, to statement: OpaquePointer, at index: Int32) {
        switch value {
        case .int(let i): sqlite3_bind_int64(statement, index, i)
        case .double(let d): sqlite3_bind_double(statement, index, d)
        case .text(let s): sqlite3_bind_text(statement, index, s, -1, SQLITE_TRANSIENT)
        case .blob(let d):
            if d.isEmpty {
                sqlite3_bind_zeroblob(statement, index, 0)
            } else {
                _ = d.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(d.count), SQLITE_TRANSIENT) }
            }
        case .null: sqlite3_bind_null(statement, index)
        }
    }

    private static func readRow(_ statement: OpaquePointer) -> SQLiteRow {
        var values: [String: SQLiteValue] = [:]
        var names: [String] = []
        for column in 0..<sqlite3_column_count(statement) {
            guard let rawName = sqlite3_column_name(statement, column) else { continue }
            let name = String(cString: rawName)
            names.append(name)
            switch sqlite3_column_type(statement, column) {
            case SQLITE_INTEGER: values[name] = .int(sqlite3_column_int64(statement, column))
            case SQLITE_FLOAT: values[name] = .double(sqlite3_column_double(statement, column))
            case SQLITE_TEXT:
                if let text = sqlite3_column_text(statement, column) { values[name] = .text(String(cString: text)) }
            case SQLITE_BLOB:
                let count = Int(sqlite3_column_bytes(statement, column))
                if let bytes = sqlite3_column_blob(statement, column), count > 0 {
                    values[name] = .blob(Data(bytes: bytes, count: count))
                } else {
                    values[name] = .blob(Data())
                }
            default: values[name] = .null
            }
        }
        return SQLiteRow(values: values, columnNames: names)
    }

    // MARK: Public API

    /// Runs one or more statements with no parameters and no results.
    public func execute(_ sql: String) throws {
        lock.lock(); defer { lock.unlock() }
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
            sqlite3_free(error)
            throw SQLiteError.step(message)
        }
    }

    @discardableResult
    public func query(_ sql: String, _ arguments: [SQLiteValue] = []) throws -> [SQLiteRow] {
        lock.lock(); defer { lock.unlock() }
        return try withStatement(sql, bind: { statement in
            for (offset, value) in arguments.enumerated() {
                Self.bind(value, to: statement, at: Int32(offset + 1))
            }
        }) { statement in
            try Self.collect(statement, handle: handle)
        }
    }

    @discardableResult
    public func query(_ sql: String, named arguments: [String: SQLiteValue]) throws -> [SQLiteRow] {
        lock.lock(); defer { lock.unlock() }
        return try withStatement(sql, bind: { statement in
            for (name, value) in arguments {
                let index = sqlite3_bind_parameter_index(statement, ":\(name)")
                if index > 0 { Self.bind(value, to: statement, at: index) }
            }
        }) { statement in
            try Self.collect(statement, handle: handle)
        }
    }

    private static func collect(_ statement: OpaquePointer, handle: OpaquePointer) throws -> [SQLiteRow] {
        var rows: [SQLiteRow] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: rows.append(readRow(statement))
            case SQLITE_DONE: return rows
            default: throw SQLiteError.step(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    /// Runs a statement that returns no rows.
    public func run(_ sql: String, _ arguments: [SQLiteValue] = []) throws {
        _ = try query(sql, arguments)
    }

    public func scalarInt(_ sql: String, _ arguments: [SQLiteValue] = []) throws -> Int64? {
        guard let row = try query(sql, arguments).first,
              let name = row.columnNames.first else { return nil }
        return row.int(name)
    }

    public func tableExists(_ name: String) throws -> Bool {
        try !query("SELECT 1 FROM sqlite_master WHERE type IN ('table','view') AND name = ?", [.text(name)]).isEmpty
    }

    public var userVersion: Int {
        (try? scalarInt("PRAGMA user_version")).flatMap { $0 }.map(Int.init) ?? 0
    }

    public func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Applies migrations whose index is beyond `user_version`, each inside its own transaction.
    /// A failing migration rolls back and leaves `user_version` at the last successful step.
    public func migrate(_ migrations: [(String, (SQLiteDatabase) throws -> Void)]) throws {
        let applied = userVersion
        guard migrations.count > applied else { return }
        for index in applied..<migrations.count {
            try transaction {
                try migrations[index].1(self)
                try execute("PRAGMA user_version = \(index + 1)")
            }
        }
    }
}
