import Foundation

/// Read-only handle on one of WhatsApp Desktop's SQLite files.
///
/// WhatsApp keeps them in WAL mode, so opening read-only while WhatsApp is running is safe and the
/// reader still sees rows that live only in the write-ahead log. The file is never copied on the
/// happy path; `open(url:)` falls back to a private snapshot only if the live file stays locked.
public struct ChatStore: Sendable {
    public let db: SQLiteDatabase
    public let url: URL

    public init(url: URL, busyTimeoutSeconds: Double = 2) throws {
        self.db = try SQLiteDatabase(url: url, readOnly: true, busyTimeoutSeconds: busyTimeoutSeconds)
        self.url = url
    }

    /// Opens with retries for transient lock errors, then falls back to a private snapshot copy.
    public static func open(url: URL, attempts: Int = 3,
                            snapshotDir: URL = FileManager.default.temporaryDirectory) throws -> ChatStore {
        var lastError: Error?
        for attempt in 0..<max(1, attempts) {
            do {
                let store = try ChatStore(url: url)
                _ = try store.db.scalarInt("SELECT 1")
                return store
            } catch let error as SQLiteError {
                if case .notFound = error { throw error }
                lastError = error
            } catch {
                lastError = error
            }
            if attempt < attempts - 1 { Thread.sleep(forTimeInterval: 0.5) }
        }
        let copy = try snapshot(of: url, into: snapshotDir)
        do {
            return try ChatStore(url: copy)
        } catch {
            throw lastError ?? error
        }
    }

    /// Copies the database with its `-wal` and `-shm` sidecars. The sidecar names must stay
    /// `<name>-wal` / `<name>-shm` or SQLite silently ignores the newest rows.
    public static func snapshot(of url: URL, into dir: URL) throws -> URL {
        let target = dir.appendingPathComponent("antifish-snapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let name = url.lastPathComponent
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try FileManager.default.copyItem(at: source, to: target.appendingPathComponent(name + suffix))
        }
        return target.appendingPathComponent(name)
    }

    public func tableExists(_ name: String) throws -> Bool {
        try db.tableExists(name)
    }
}
