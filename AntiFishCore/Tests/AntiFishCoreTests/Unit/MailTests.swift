import XCTest
@testable import AntiFishCore

/// PhishGuard hands back JSON. These tests pin the shape AntiFish reads, so a change in the
/// vendored engine's output is caught here rather than showing up as an empty inbox.
final class MailTests: XCTestCase {
    private let sample = """
    {"scanned": 400, "account": "me@example.com",
     "tiers": {"danger": 83, "caution": 48, "safe": 225},
     "messages": [
       {"localID": "emlx:1", "path": "/m/1.emlx", "mailbox": "All Mail",
        "subject": "Only 7 Days Left to Apply", "fromAddress": "no-reply@nickarachi.com",
        "fromDisplay": "NIC Karachi", "fromDomain": "nickarachi.com",
        "receivedAt": "2026-06-01T07:10:03+00:00", "snippet": "Apply now",
        "tier": "danger", "score": 0.98,
        "headline": "This message fails the checks its own domain publishes.",
        "findings": [{"code": "DMARC_FAIL", "title": "DMARC_FAIL", "detail": "d= mismatch", "weight": 0.7}],
        "mitigating": [{"code": "RECURRING_SENDER", "detail": "seen 4 times"}],
        "isFromMe": false, "attachmentNames": ["flyer.png"], "hasImages": true},
       {"localID": "emlx:2", "path": "/m/2.emlx", "mailbox": "INBOX",
        "subject": "Your invoice", "fromAddress": "billing@getlago.com",
        "fromDisplay": "Lago", "fromDomain": "getlago.com",
        "receivedAt": "2026-05-30T09:00:00+00:00", "snippet": "Invoice attached",
        "tier": "safe", "score": 0.2, "headline": "Nothing stood out.",
        "findings": [], "mitigating": [], "isFromMe": false,
        "attachmentNames": [], "hasImages": false}
     ]}
    """

    func testDecodesAScan() throws {
        let scan = try MailScan.decode(Data(sample.utf8))
        XCTAssertEqual(scan.scanned, 400)
        XCTAssertEqual(scan.account, "me@example.com")
        XCTAssertEqual(scan.messages.count, 2)
        XCTAssertEqual(scan.tiers["danger"], 83)
    }

    func testMessageFields() throws {
        let message = try XCTUnwrap(try MailScan.decode(Data(sample.utf8)).messages.first)
        XCTAssertEqual(message.id, "emlx:1")
        XCTAssertEqual(message.subject, "Only 7 Days Left to Apply")
        XCTAssertEqual(message.fromDisplay, "NIC Karachi")
        XCTAssertEqual(message.fromDomain, "nickarachi.com")
        XCTAssertEqual(message.tier, .danger)
        XCTAssertEqual(message.score, 0.98, accuracy: 1e-6)
        XCTAssertEqual(message.findings.first?.code, "DMARC_FAIL")
        XCTAssertEqual(message.findings.first?.detail, "d= mismatch")
        XCTAssertTrue(message.hasImages)
        XCTAssertEqual(message.attachmentNames, ["flyer.png"])
        XCTAssertNotNil(message.date)
    }

    func testTierOrderingPutsDangerFirst() {
        XCTAssertLessThan(MailTier.danger.rank, MailTier.caution.rank)
        XCTAssertLessThan(MailTier.caution.rank, MailTier.safe.rank)
        XCTAssertTrue(MailTier.danger.isAlarming)
        XCTAssertFalse(MailTier.caution.isAlarming)
        XCTAssertFalse(MailTier.safe.isAlarming)
    }

    func testUnknownTierDoesNotThrow() throws {
        let odd = sample.replacingOccurrences(of: "\"tier\": \"danger\"", with: "\"tier\": \"wat\"")
        let scan = try MailScan.decode(Data(odd.utf8))
        XCTAssertEqual(scan.messages.first?.tier, .unknown)
    }

    /// Every finding code PhishGuard emits should read as a sentence, not an identifier.
    func testFindingCodesAreExplainedInPlainWords() {
        XCTAssertEqual(MailFinding.explain("DMARC_FAIL"),
                       "The sender's own domain says this message should have been rejected.")
        XCTAssertEqual(MailFinding.explain("DISPLAY_NAME_IMPERSONATION"),
                       "The name on the message does not belong to the address that sent it.")
        XCTAssertEqual(MailFinding.explain("URL_ANCHOR_MISMATCH"),
                       "A link shows one address and goes to another.")
        // An unmapped code still has to produce something readable.
        XCTAssertFalse(MailFinding.explain("SOME_NEW_CODE").isEmpty)
        XCTAssertFalse(MailFinding.explain("SOME_NEW_CODE").contains("_"))
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try MailScan.decode(Data("not json".utf8)))
    }
}
