import Foundation

public struct VideoVerdict: Sendable, Codable, Equatable {
    public let image: ImageVerdict
    public let framesChecked: Int
    public let framesFlagged: Int

    public var isAlarming: Bool { image.isAlarming }

    public init(image: ImageVerdict, framesChecked: Int, framesFlagged: Int) {
        self.image = image
        self.framesChecked = framesChecked
        self.framesFlagged = framesFlagged
    }

    /// The strongest frame decides: a clip only has to be generated somewhere to be generated.
    public static func from(peakAI: Double, peakDeepfake: Double,
                            framesChecked: Int, framesFlagged: Int) -> VideoVerdict {
        VideoVerdict(image: ImageVerdict.from(aiGenerated: peakAI, deepfake: peakDeepfake),
                     framesChecked: framesChecked, framesFlagged: framesFlagged)
    }

    /// How many frames agreed, which is what a person can actually judge.
    public var summary: String {
        let count = framesFlagged == 0 ? "none" : String(framesFlagged)
        return "\(count) of \(framesChecked) frames look generated"
    }
}

/// Checks a video by checking frames inside it.
///
/// The stronger method scores faces with a PyTorch model, which is a 2.5 GB download. This takes
/// the road already paid for: pull a few stills with ffmpeg and run each through the same image
/// check the rest of the app uses.
///
/// Where the frames come from matters more than how many. Measured on five labelled clips, five
/// frames spread across the clip got all five right; three frames from the opening called a real
/// selfie AI-generated at 0.99, because an opening frame is often dark or half-rendered.
public struct VideoCheck: Sendable {
    public let credentials: ImageCheck.Credentials?
    public let scriptURL: URL?
    /// Five, spread out. Fewer misses a face swap; taking them from the start invents one.
    public let frameCount: Int

    public init(credentials: ImageCheck.Credentials? = ImageCheck.Credentials.loadDefault(),
                scriptURL: URL? = VideoCheck.defaultScriptURL(),
                frameCount: Int = 5) {
        self.credentials = credentials
        self.scriptURL = scriptURL
        self.frameCount = frameCount
    }

    public static func defaultScriptURL() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Tools/videobridge.py"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tools/videobridge.py")
        return FileManager.default.fileExists(atPath: repo.path) ? repo : nil
    }

    public var isConfigured: Bool { credentials != nil && scriptURL != nil }

    public var unavailableReason: String {
        if credentials == nil {
            return "Video checking is off. It needs SightEngine keys in a .env file, and it sends a few frames to their service."
        }
        if scriptURL == nil { return "The video bridge is missing." }
        return ""
    }

    public enum Outcome: Sendable, Equatable {
        case checked(VideoVerdict)
        case failed(CheckFailure)
    }

    public func check(videoAt url: URL) throws -> Outcome {
        guard let credentials, let scriptURL else {
            return .failed(CheckFailure(kind: .notConfigured,
                                        message: CheckFailureKind.notConfigured.defaultMessage))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptURL.path, url.path, "--frames", String(frameCount)]
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

        guard let row = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failed(CheckFailure(kind: .failed, message: CheckFailureKind.failed.defaultMessage))
        }
        if let error = row["error"] as? String {
            return .failed(CheckFailure.from(errorText: error))
        }
        guard process.terminationStatus == 0 else {
            return .failed(CheckFailure(kind: .failed, message: CheckFailureKind.failed.defaultMessage))
        }
        return .checked(VideoVerdict.from(peakAI: row["ai_generated"] as? Double ?? 0,
                                          peakDeepfake: row["deepfake"] as? Double ?? 0,
                                          framesChecked: row["framesChecked"] as? Int ?? 0,
                                          framesFlagged: row["framesFlagged"] as? Int ?? 0))
    }
}
