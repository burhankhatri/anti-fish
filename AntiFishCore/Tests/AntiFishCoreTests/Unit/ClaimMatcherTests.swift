import XCTest
@testable import AntiFishCore

/// An unsaved number's profile name is the claim an impersonator makes. Matching it against the
/// user's enrolled contacts is what turns "unknown voice" into "claims to be Abdul".
final class ClaimMatcherTests: XCTestCase {
    private let names = ["a@lid": "Abdul Test", "k@lid": "Karim Élan", "jo@lid": "Jo Li"]
    private let enrolled = ["a@lid", "k@lid", "jo@lid"]

    func testNormalizeStripsCaseAccentsAndPunctuation() {
        XCTAssertEqual(ClaimMatcher.normalize("  Karim  Élan!! "), "karim elan")
        XCTAssertEqual(ClaimMatcher.normalize("ABDUL-TEST"), "abdultest")
        XCTAssertEqual(ClaimMatcher.normalize("🔥"), "")
    }

    func testFullNameMatchesRegardlessOfCase() {
        XCTAssertEqual(ClaimMatcher.claimedJID(pushName: "abdul test", enrolled: enrolled, names: names), "a@lid")
        XCTAssertEqual(ClaimMatcher.claimedJID(pushName: "Karim Élan", enrolled: enrolled, names: names), "k@lid")
    }

    func testFirstNameMatchesOnlyWhenItIsDistinctiveEnough() {
        XCTAssertEqual(ClaimMatcher.claimedJID(pushName: "Karim 🔥", enrolled: enrolled, names: names), "k@lid")
        XCTAssertNil(ClaimMatcher.claimedJID(pushName: "Jo", enrolled: enrolled, names: names),
                     "a two-letter first name is too weak to accuse anyone over")
        XCTAssertEqual(ClaimMatcher.claimedJID(pushName: "Jo Li", enrolled: enrolled, names: names), "jo@lid")
    }

    func testNoClaimWhenNothingMatches() {
        XCTAssertNil(ClaimMatcher.claimedJID(pushName: "Someone Else", enrolled: enrolled, names: names))
        XCTAssertNil(ClaimMatcher.claimedJID(pushName: nil, enrolled: enrolled, names: names))
        XCTAssertNil(ClaimMatcher.claimedJID(pushName: "", enrolled: enrolled, names: names))
        XCTAssertNil(ClaimMatcher.claimedJID(pushName: "Abdul", enrolled: [], names: names))
    }

    func testOnlyEnrolledContactsCanBeClaimed() {
        XCTAssertNil(ClaimMatcher.claimedJID(pushName: "Abdul Test", enrolled: ["k@lid"], names: names))
    }
}
