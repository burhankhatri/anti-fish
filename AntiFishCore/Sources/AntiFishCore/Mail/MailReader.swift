import Foundation

public enum MailReaderError: Error, Equatable {
    case bridgeMissing(String)
    case bridgeFailed(String)
}

/// Runs PhishGuard over the mail Mail.app has already downloaded.
///
/// The engine is Python and stays Python: porting four layers of detection to Swift would be four
/// layers of new bugs. The bridge script is invoked as a subprocess and hands back JSON.
public struct MailReader: Sendable {
    public let mailRoot: URL
    public let cacheURL: URL
    public let bridgeURL: URL?

    public init(mailRoot: URL = MailReader.defaultMailRoot,
                cacheURL: URL = MailReader.defaultCacheURL(),
                bridgeURL: URL? = MailReader.defaultBridgeURL()) {
        self.mailRoot = mailRoot
        self.cacheURL = cacheURL
        self.bridgeURL = bridgeURL
    }

    public static var defaultMailRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mail")
    }

    public static func defaultCacheURL() -> URL {
        AppDatabase.defaultURL().deletingLastPathComponent().appendingPathComponent("mail-scan.json")
    }

    /// Inside a built app the bridge ships in Resources; in development it sits in the repo.
    public static func defaultBridgeURL() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Tools/phishbridge.py"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tools/phishbridge.py")
        return FileManager.default.fileExists(atPath: repo.path) ? repo : nil
    }

    /// True when Mail.app has downloaded at least one message.
    public var isAvailable: Bool {
        guard let walker = FileManager.default.enumerator(at: mailRoot,
                                                          includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles]) else {
            return false
        }
        for case let url as URL in walker where url.pathExtension == "emlx" {
            return true
        }
        return false
    }

    public func cachedScan() throws -> MailScan? {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return nil }
        return try MailScan.decode(try Data(contentsOf: cacheURL))
    }

    /// Runs the bridge and caches the result. Minutes on a large mailbox, so callers run it off
    /// the main thread and show what is cached meanwhile.
    @discardableResult
    public func scan(limit: Int = 400, pick: Int = 30) throws -> MailScan {
        guard let bridgeURL else { throw MailReaderError.bridgeMissing("Tools/phishbridge.py") }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", bridgeURL.path, "scan",
                             "--limit", String(limit), "--pick", String(pick)]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        guard process.terminationStatus == 0, !data.isEmpty else {
            throw MailReaderError.bridgeFailed(errorText.isEmpty ? "no output" : String(errorText.suffix(400)))
        }
        let scan = try MailScan.decode(data)
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: cacheURL)
        return scan
    }
}
