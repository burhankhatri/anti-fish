import Foundation
import XCTest
@testable import AntiFishCore

enum TestEnv {
    /// Models live in the app's resource folder (gitignored, fetched by `make models`) unless overridden.
    static var modelsDir: URL {
        if let p = ProcessInfo.processInfo.environment["ANTIFISH_MODELS_DIR"] {
            return URL(fileURLWithPath: p)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Support
            .deletingLastPathComponent() // AntiFishCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // AntiFishCore
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("AntiFish/Resources/Models")
    }

    static var speakerModelPath: String {
        modelsDir.appendingPathComponent("wespeaker_en_voxceleb_resnet34_LM.onnx").path
    }

    static var vadModelPath: String {
        modelsDir.appendingPathComponent("silero_vad.onnx").path
    }

    static var hasModels: Bool {
        FileManager.default.fileExists(atPath: speakerModelPath)
            && FileManager.default.fileExists(atPath: vadModelPath)
    }

    static var realWA: Bool {
        ProcessInfo.processInfo.environment["ANTIFISH_REAL_WA"] == "1" && ContainerLocator().isInstalled
    }

    static func skipUnlessModels() throws {
        try XCTSkipUnless(hasModels, "models missing at \(modelsDir.path): run `make models`")
    }

    static func skipUnlessRealWA() throws {
        try XCTSkipUnless(realWA, "set ANTIFISH_REAL_WA=1 on a Mac with WhatsApp Desktop linked")
    }

    static func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("antifish-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
