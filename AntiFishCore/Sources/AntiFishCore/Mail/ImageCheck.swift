import Foundation

public enum ImageVerdictKind: String, Sendable, Codable, Equatable {
    case aiGenerated, faceSwapped, authentic, unchecked

    public var title: String {
        switch self {
        case .aiGenerated: "Made by AI"
        case .faceSwapped: "Face swapped"
        case .authentic: "Looks real"
        case .unchecked: "Not checked"
        }
    }
}

public struct ImageVerdict: Sendable, Codable, Equatable {
    public let kind: ImageVerdictKind
    public let confidence: Double
    public let aiGenerated: Double
    public let deepfake: Double

    public var isAlarming: Bool { kind == .aiGenerated || kind == .faceSwapped }

    public init(kind: ImageVerdictKind, confidence: Double, aiGenerated: Double = 0, deepfake: Double = 0) {
        self.kind = kind
        self.confidence = confidence
        self.aiGenerated = aiGenerated
        self.deepfake = deepfake
    }

    /// The same rule deepfake-check uses: whichever signal is strongest, if either clears the bar.
    public static let threshold = 0.5

    public static func from(aiGenerated: Double, deepfake: Double) -> ImageVerdict {
        if aiGenerated >= threshold || deepfake >= threshold {
            return aiGenerated >= deepfake
                ? ImageVerdict(kind: .aiGenerated, confidence: aiGenerated,
                               aiGenerated: aiGenerated, deepfake: deepfake)
                : ImageVerdict(kind: .faceSwapped, confidence: deepfake,
                               aiGenerated: aiGenerated, deepfake: deepfake)
        }
        return ImageVerdict(kind: .authentic, confidence: 1 - max(aiGenerated, deepfake),
                            aiGenerated: aiGenerated, deepfake: deepfake)
    }
}

/// Checks whether a shared image was made by AI or had a face swapped into it.
///
/// This is the one part of AntiFish that leaves the machine: the image is sent to SightEngine.
/// It stays off until credentials exist, and the interface says so wherever a result appears.
public struct ImageCheck: Sendable {
    public struct Credentials: Sendable, Equatable {
        public let user: String
        public let secret: String

        public init(user: String, secret: String) {
            self.user = user
            self.secret = secret
        }

        /// Reads a `.env` in the shape deepfake-check documents. Returns nil unless both are present.
        public static func load(from url: URL) -> Credentials? {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            var values: [String: String] = [:]
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { continue }
                let key = String(trimmed[trimmed.startIndex..<equals]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { values[key] = value }
            }
            guard let user = values["SIGHTENGINE_USER"], let secret = values["SIGHTENGINE_SECRET"] else {
                return nil
            }
            return Credentials(user: user, secret: secret)
        }

        public static func loadDefault() -> Credentials? {
            let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".env")
            if let found = load(from: repo) { return found }
            let support = AppDatabase.defaultURL().deletingLastPathComponent().appendingPathComponent(".env")
            return load(from: support)
        }
    }

    public let credentials: Credentials?
    public let scriptURL: URL?

    public init(credentials: Credentials? = Credentials.loadDefault(),
                scriptURL: URL? = ImageCheck.defaultScriptURL()) {
        self.credentials = credentials
        self.scriptURL = scriptURL
    }

    public static func defaultScriptURL() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Vendor/deepfake/detect.py"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Vendor/deepfake/detect.py")
        return FileManager.default.fileExists(atPath: repo.path) ? repo : nil
    }

    public var isConfigured: Bool { credentials != nil && scriptURL != nil }

    public var unavailableReason: String {
        if credentials == nil {
            return "Image checking is off. It needs SightEngine keys in a .env file, and it sends the image to their service."
        }
        if scriptURL == nil { return "The deepfake-check script is missing." }
        return ""
    }

    /// Sends one image to SightEngine through deepfake-check and returns its verdict.
    /// The image leaves this Mac.
    public func check(imageAt url: URL) throws -> ImageVerdict {
        guard let credentials, let scriptURL else { return ImageVerdict(kind: .unchecked, confidence: 0) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptURL.path, url.path, "--json"]
        var environment = ProcessInfo.processInfo.environment
        environment["SIGHTENGINE_USER"] = credentials.user
        environment["SIGHTENGINE_SECRET"] = credentials.secret
        process.environment = environment
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let parsed = try? JSONSerialization.jsonObject(with: data) else {
            return ImageVerdict(kind: .unchecked, confidence: 0)
        }
        let row: [String: Any]?
        if let list = parsed as? [[String: Any]] { row = list.first }
        else { row = parsed as? [String: Any] }
        guard let row else { return ImageVerdict(kind: .unchecked, confidence: 0) }
        return ImageVerdict.from(aiGenerated: row["ai_generated"] as? Double ?? 0,
                                 deepfake: row["deepfake"] as? Double ?? 0)
    }
}
