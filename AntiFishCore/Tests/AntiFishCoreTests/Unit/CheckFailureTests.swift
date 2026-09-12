import XCTest
@testable import AntiFishCore

/// A check that did not happen must never look like a check that passed. The free SightEngine
/// plan has a daily cap; when it was hit, the app drew a green tick reading "Not checked 0%",
/// which tells a non-technical user the opposite of the truth.
final class CheckFailureTests: XCTestCase {
    func testAnUncheckedResultIsNotAPass() {
        let unchecked = ImageVerdict(kind: .unchecked, confidence: 0)
        XCTAssertFalse(unchecked.isAlarming)
        XCTAssertFalse(unchecked.isReassuring, "nothing was checked, so nothing is reassuring")
    }

    func testAnAuthenticResultIsAPass() {
        XCTAssertTrue(ImageVerdict.from(aiGenerated: 0.02, deepfake: 0.01).isReassuring)
    }

    func testAFlaggedResultIsNeitherReassuringNorSilent() {
        let flagged = ImageVerdict.from(aiGenerated: 0.95, deepfake: 0.01)
        XCTAssertTrue(flagged.isAlarming)
        XCTAssertFalse(flagged.isReassuring)
    }

    /// The reason has to survive to the interface, or the user sees a shrug with no explanation.
    func testFailureCarriesItsReason() {
        let quota = CheckFailure.from(errorText: "Daily usage limit reached. You are under a Free plan.")
        XCTAssertEqual(quota.kind, .quotaReached)
        XCTAssertTrue(quota.message.contains("daily limit"))

        let offline = CheckFailure.from(errorText: "URLError: The Internet connection appears to be offline")
        XCTAssertEqual(offline.kind, .offline)

        let creds = CheckFailure.from(errorText: "no SightEngine credentials")
        XCTAssertEqual(creds.kind, .notConfigured)

        let other = CheckFailure.from(errorText: "something exploded")
        XCTAssertEqual(other.kind, .failed)
        XCTAssertFalse(other.message.isEmpty)
    }

    func testEveryFailureReadsAsPlainWords() {
        for kind in CheckFailureKind.allCases {
            let message = CheckFailure(kind: kind, message: kind.defaultMessage).message
            XCTAssertFalse(message.isEmpty)
            XCTAssertFalse(message.contains("_"), "\(kind) still reads like a constant")
            XCTAssertFalse(message.lowercased().contains("error:"), "\(kind) leaks a raw error")
        }
    }
}
