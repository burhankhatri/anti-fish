import XCTest
import AppKit
@testable import AntiFishCore

/// Reads the words inside a picture so a doctored payment screenshot can be judged by what it
/// says. Uses Apple's own recogniser, so it runs on this Mac with no service and no quota.
final class ImageTextTests: XCTestCase {
    /// Draws text into a PNG so the test exercises the real recogniser rather than a stub.
    private func image(containing text: String) throws -> URL {
        let size = NSSize(width: 640, height: 200)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        (text as NSString).draw(
            at: NSPoint(x: 24, y: 90),
            withAttributes: [.font: NSFont.systemFont(ofSize: 40, weight: .semibold),
                             .foregroundColor: NSColor.black])
        image.unlockFocus()

        let url = try TestEnv.tempDir().appendingPathComponent("text.png")
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "test", code: 1)
        }
        try png.write(to: url)
        return url
    }

    func testReadsWordsOutOfAPicture() throws {
        let url = try image(containing: "Rs. 25,000 received")
        let text = try ImageText.read(at: url)
        XCTAssertTrue(text.lowercased().contains("25,000") || text.lowercased().contains("25000"),
                      "got: \(text)")
        XCTAssertTrue(text.lowercased().contains("received"), "got: \(text)")
    }

    /// The whole point: a payment screenshot looks like an ordinary photo to a pixel model, and
    /// says something specific to a reader.
    func testAPaymentScreenshotIsJudgedByItsWords() throws {
        let url = try image(containing: "Transferred Rs. 25,000 to your account")
        let assessment = try ImageText.assess(at: url, senderIsKnown: false)
        XCTAssertTrue(assessment.signals.contains(.paymentClaim))
        XCTAssertTrue(assessment.isWorrying)
    }

    func testAnOrdinaryPictureSaysNothingWorrying() throws {
        let url = try image(containing: "Happy birthday Amma")
        XCTAssertFalse(try ImageText.assess(at: url, senderIsKnown: true).isWorrying)
    }

    func testAPictureWithNoTextIsHandled() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("blank.png")
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.lockFocus(); NSColor.gray.setFill(); NSRect(x: 0, y: 0, width: 100, height: 100).fill(); image.unlockFocus()
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: url)
        XCTAssertTrue(try ImageText.read(at: url).isEmpty)
    }

    func testAMissingFileThrows() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("nope.png")
        XCTAssertThrowsError(try ImageText.read(at: url))
    }
}
