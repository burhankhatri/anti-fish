/// Cosine-similarity thresholds in the centred embedding space.
///
/// The defaults come from measuring ten real speakers on this Mac: same-speaker scores average
/// 0.63 and different-speaker scores average -0.08. They hold until `Calibrator` has enough
/// enrolled contacts to learn the user's own distribution.
public struct Thresholds: Sendable, Equatable, Codable {
    public var reject: Float
    public var match: Float
    public var calibrated: Bool

    public init(reject: Float = 0.25, match: Float = 0.45, calibrated: Bool = false) {
        self.reject = reject
        self.match = match
        self.calibrated = calibrated
    }
}
