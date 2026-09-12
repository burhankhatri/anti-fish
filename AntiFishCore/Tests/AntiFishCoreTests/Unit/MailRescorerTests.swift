import XCTest
@testable import AntiFishCore

/// PhishGuard's weights were tuned on a different mailbox. On this one they rank a marketing
/// newsletter (0.94) above an actual phishing campaign (0.82), because tracked links look exactly
/// like disguised links. Measured across 157 spam messages: URL_BRAND_IN_SUBDOMAIN appeared on
/// five legitimate bulk senders and zero phishing messages; URL_FREE_HOSTING on three phishing
/// messages and zero legitimate ones.
///
/// This layer does not change PhishGuard's scoring. It only refuses to call something phishing
/// when the sole evidence is link shape and the domain's own DNS vouches for the message.
final class MailRescorerTests: XCTestCase {
    private func finding(_ code: String, _ weight: Double = 0.5) -> MailFinding {
        MailFinding(code: code, detail: "", weight: weight)
    }

    private let vouched = [MailFinding(code: "DMARC_PASS"), MailFinding(code: "RECURRING_SENDER")]

    func testTrackedLinksAloneFromAVouchedSenderAreNotPhishing() {
        let tier = MailRescorer.adjust(tier: .danger,
                                       findings: [finding("URL_BRAND_IN_SUBDOMAIN", 0.76),
                                                  finding("URL_ANCHOR_MISMATCH", 0.74)],
                                       mitigating: vouched)
        XCTAssertEqual(tier, .caution, "a newsletter with tracking links is worth a look, not an alarm")
    }

    func testAFailedSignatureIsStillPhishing() {
        let tier = MailRescorer.adjust(tier: .danger,
                                       findings: [finding("DKIM_FAIL", 0.45),
                                                  finding("URL_FREE_HOSTING", 0.45)],
                                       mitigating: [MailFinding(code: "ARC_FORWARDED")])
        XCTAssertEqual(tier, .danger)
    }

    /// Even a sender you hear from constantly can be spoofed, so hard evidence always wins.
    func testHardEvidenceBeatsAVouchedSender() {
        for code in ["DKIM_FAIL", "DMARC_FAIL", "SPF_FAIL", "URL_FREE_HOSTING",
                     "LOOKALIKE_DOMAIN", "ATTACHMENT_EXECUTABLE", "DISPLAY_NAME_IMPERSONATION"] {
            let tier = MailRescorer.adjust(tier: .danger,
                                           findings: [finding(code), finding("URL_ANCHOR_MISMATCH")],
                                           mitigating: vouched)
            XCTAssertEqual(tier, .danger, "\(code) should survive the adjustment")
        }
    }

    func testAnUnvouchedSenderIsLeftAlone() {
        let tier = MailRescorer.adjust(tier: .danger,
                                       findings: [finding("URL_ANCHOR_MISMATCH", 0.74)],
                                       mitigating: [])
        XCTAssertEqual(tier, .danger, "without DMARC passing there is nothing vouching for it")
    }

    func testPassingDMARCAloneIsNotEnough() {
        let tier = MailRescorer.adjust(tier: .danger,
                                       findings: [finding("URL_ANCHOR_MISMATCH", 0.74)],
                                       mitigating: [MailFinding(code: "DMARC_PASS")])
        XCTAssertEqual(tier, .danger, "anyone can pass DMARC on a domain they just registered")
    }

    func testCautionAndSafeAreNeverChanged() {
        XCTAssertEqual(MailRescorer.adjust(tier: .caution, findings: [], mitigating: vouched), .caution)
        XCTAssertEqual(MailRescorer.adjust(tier: .safe, findings: [], mitigating: vouched), .safe)
    }

    func testTheAdjustmentIsExplainedWhenItHappens() {
        XCTAssertTrue(MailRescorer.wasAdjusted(from: .danger, to: .caution))
        XCTAssertFalse(MailRescorer.wasAdjusted(from: .danger, to: .danger))
        XCTAssertFalse(MailRescorer.note.isEmpty)
    }
}
