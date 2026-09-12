import XCTest
@testable import AntiFishCore

final class MailReaderTests: XCTestCase {
    func testCachePathLivesBesideTheAppDatabase() {
        XCTAssertEqual(MailReader.defaultCacheURL().lastPathComponent, "mail-scan.json")
        XCTAssertTrue(MailReader.defaultCacheURL().path.contains("AntiFish"))
    }

    func testMailIsPresentWhenTheMailFolderExists() throws {
        let root = try TestEnv.tempDir()
        XCTAssertFalse(MailReader(mailRoot: root).isAvailable, "an empty folder holds no mail")
        let box = root.appendingPathComponent("V10/acct/INBOX.mbox/Data/Messages", isDirectory: true)
        try FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
        try Data("1\nx".utf8).write(to: box.appendingPathComponent("1.emlx"))
        XCTAssertTrue(MailReader(mailRoot: root).isAvailable)
    }

    func testReadsACachedScan() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("mail-scan.json")
        try Data("""
        {"scanned":2,"account":"a@b.c","tiers":{"safe":2},"messages":[]}
        """.utf8).write(to: url)
        let scan = try XCTUnwrap(try MailReader(cacheURL: url).cachedScan())
        XCTAssertEqual(scan.scanned, 2)
        XCTAssertEqual(scan.account, "a@b.c")
    }

    func testMissingCacheIsNilRatherThanAnError() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("absent.json")
        XCTAssertNil(try MailReader(cacheURL: url).cachedScan())
    }

    func testCorruptCacheThrows() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("bad.json")
        try Data("{".utf8).write(to: url)
        XCTAssertThrowsError(try MailReader(cacheURL: url).cachedScan())
    }
}

/// The image check is the one part of AntiFish that uses the network, so it stays off until
/// credentials are present and says so plainly.
final class ImageCheckTests: XCTestCase {
    func testDisabledWithoutCredentials() {
        let check = ImageCheck(credentials: nil)
        XCTAssertFalse(check.isConfigured)
        XCTAssertTrue(check.unavailableReason.contains("SightEngine"))
    }

    func testConfiguredWithCredentials() {
        let check = ImageCheck(credentials: .init(user: "u", secret: "s"))
        XCTAssertTrue(check.isConfigured)
    }

    func testCredentialsLoadFromAnEnvFile() throws {
        let url = try TestEnv.tempDir().appendingPathComponent(".env")
        try Data("""
        # a comment
        SIGHTENGINE_USER=12345
        SIGHTENGINE_SECRET=abcdef

        """.utf8).write(to: url)
        let creds = try XCTUnwrap(ImageCheck.Credentials.load(from: url))
        XCTAssertEqual(creds.user, "12345")
        XCTAssertEqual(creds.secret, "abcdef")
    }

    func testMissingEnvFileGivesNoCredentials() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("nope.env")
        XCTAssertNil(ImageCheck.Credentials.load(from: url))
    }

    func testHalfAnEnvFileGivesNoCredentials() throws {
        let url = try TestEnv.tempDir().appendingPathComponent(".env")
        try Data("SIGHTENGINE_USER=12345\n".utf8).write(to: url)
        XCTAssertNil(ImageCheck.Credentials.load(from: url), "a user without a secret is unusable")
    }

    func testVerdictFromScores() {
        XCTAssertEqual(ImageVerdict.from(aiGenerated: 0.95, deepfake: 0.02).kind, .aiGenerated)
        XCTAssertEqual(ImageVerdict.from(aiGenerated: 0.02, deepfake: 0.91).kind, .faceSwapped)
        XCTAssertEqual(ImageVerdict.from(aiGenerated: 0.05, deepfake: 0.03).kind, .authentic)
        // Both high: the stronger signal wins, and it is still called out.
        XCTAssertEqual(ImageVerdict.from(aiGenerated: 0.99, deepfake: 0.80).kind, .aiGenerated)
    }

    func testVerdictConfidenceIsTheDecidingScore() {
        XCTAssertEqual(ImageVerdict.from(aiGenerated: 0.95, deepfake: 0.02).confidence, 0.95, accuracy: 1e-6)
        XCTAssertEqual(ImageVerdict.from(aiGenerated: 0.02, deepfake: 0.91).confidence, 0.91, accuracy: 1e-6)
    }

    func testAuthenticVerdictIsNotAlarming() {
        XCTAssertFalse(ImageVerdict.from(aiGenerated: 0.05, deepfake: 0.03).isAlarming)
        XCTAssertTrue(ImageVerdict.from(aiGenerated: 0.95, deepfake: 0.02).isAlarming)
    }
}
