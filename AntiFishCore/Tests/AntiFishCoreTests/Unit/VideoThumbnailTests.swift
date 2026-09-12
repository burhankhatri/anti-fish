import AVFoundation
import CoreGraphics
import XCTest
@testable import AntiFishCore

/// A clip in the thread showed as a grey play icon, so the only way to know what it was was to
/// open WhatsApp. A still from the clip says what it is at a glance.
final class VideoThumbnailTests: XCTestCase {
    /// Writes a real clip: `openingBlackSeconds` of black, then red to the end.
    private func makeClip(seconds: Double, openingBlackSeconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumb-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let size = CGSize(width: 160, height: 120)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                           sourcePixelBufferAttributes: nil)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let fps = 10
        for frame in 0..<Int(seconds * Double(fps)) {
            let time = Double(frame) / Double(fps)
            let isBlack = time < openingBlackSeconds
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height),
                                kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let buffer else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                    width: Int(size.width), height: Int(size.height),
                                    bitsPerComponent: 8,
                                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                        | CGBitmapInfo.byteOrder32Little.rawValue)
            context?.setFillColor(isBlack ? CGColor(red: 0, green: 0, blue: 0, alpha: 1)
                                          : CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context?.fill(CGRect(origin: .zero, size: size))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            while !input.isReadyForMoreMediaData { usleep(2000) }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame),
                                                                timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        let done = expectation(description: "written")
        writer.finishWriting { done.fulfill() }
        wait(for: [done], timeout: 20)
        return url
    }

    private func averageRed(_ image: CGImage) -> Int {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &pixels, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let reds = stride(from: 0, to: pixels.count, by: 4).map { Int(pixels[$0]) }
        return reds.reduce(0, +) / max(reds.count, 1)
    }

    func testAPosterFrameIsProducedForAClip() throws {
        let url = try makeClip(seconds: 2, openingBlackSeconds: 0)
        defer { try? FileManager.default.removeItem(at: url) }
        let poster = try XCTUnwrap(VideoThumbnail.poster(for: url))
        XCTAssertEqual(poster.width, 160)
        XCTAssertEqual(poster.height, 120)
    }

    /// The very first frame of a phone video is often black or half-rendered, which would put an
    /// empty rectangle in the thread and tell the reader nothing.
    func testThePosterSkipsABlackOpening() throws {
        let url = try makeClip(seconds: 3, openingBlackSeconds: 1.0)
        defer { try? FileManager.default.removeItem(at: url) }
        let poster = try XCTUnwrap(VideoThumbnail.poster(for: url))
        XCTAssertGreaterThan(averageRed(poster), 128, "a black opening frame was picked")
    }

    func testAFileThatIsNotAVideoGivesNothingRatherThanThrowing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-video-\(UUID().uuidString).mp4")
        try Data("this is not a video".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(VideoThumbnail.poster(for: url))
    }
}
