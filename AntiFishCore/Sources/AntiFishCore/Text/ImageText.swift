import AppKit
import Foundation
import Vision

public enum ImageTextError: Error, Equatable {
    case unreadable(String)
}

/// Reads the words inside a picture.
///
/// A doctored bank-transfer screenshot is the scam that pixel analysis cannot see: it is a genuine
/// screenshot with edited numbers, so nothing about it was generated and nothing was face-swapped.
/// What gives it away is what it says. Apple's recogniser does this on the machine, which also
/// means it keeps working when the hosted image check has run out of quota.
public enum ImageText {
    public static func read(at url: URL) throws -> String {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageTextError.unreadable(url.lastPathComponent)
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        do {
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
        } catch {
            throw ImageTextError.unreadable(url.lastPathComponent)
        }

        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    /// Reads the picture, then judges the words the same way a message is judged.
    public static func assess(at url: URL, senderIsKnown: Bool) throws -> ScamAssessment {
        ScamText.assess(try read(at: url), senderIsKnown: senderIsKnown)
    }
}
