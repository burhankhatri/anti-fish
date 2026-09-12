/// The one number every verdict turns on, in the centred embedding space.
///
/// A band between "certainly not them" and "certainly them" sounds careful but is useless in
/// practice: on real data 54% of genuine notes landed inside it and came back as "inconclusive",
/// which tells the reader nothing. A single decision point gives every note an answer, and
/// `errorRate` says honestly how often that answer is wrong.
///
/// The default comes from measuring 28 real contacts before calibration has run.
public struct Thresholds: Sendable, Equatable, Codable {
    public var decision: Float
    public var calibrated: Bool

    public init(decision: Float = 0.36, calibrated: Bool = false) {
        self.decision = decision
        self.calibrated = calibrated
    }
}
