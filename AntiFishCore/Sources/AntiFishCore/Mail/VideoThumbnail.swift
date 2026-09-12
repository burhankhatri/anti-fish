import AVFoundation
import CoreGraphics
import Foundation

/// A still taken from a clip, so a video in the thread looks like what it is.
///
/// Nothing here leaves the Mac: this is AVFoundation reading a local file. The frames the check
/// uploads are a separate matter, and are only sent when the reader asks for them.
public enum VideoThumbnail {
    /// A phone video usually opens black or half-rendered, so the still is taken a little in.
    /// Short clips fall back to their midpoint, which is always inside the clip.
    public static func poster(for url: URL, preferring seconds: Double = 1.0) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let length = CMTimeGetSeconds(duration)
        guard length.isFinite, length > 0 else { return nil }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Without a tight tolerance the generator may return a frame far from the one asked for,
        // which for a black opening is exactly the frame being avoided.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let target = length > seconds * 2 ? seconds : length / 2
        let time = CMTime(seconds: target, preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }
}
