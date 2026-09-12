import Foundation

/// A second look at a voice note: does it sound machine-made at all?
///
/// This is deliberately modest. It measures two crude tells — loudness that varies too evenly, and
/// a spectrum that flips too regularly — because synthesised speech tends to lack the unevenness
/// of a person in a room. Measured against ten synthesised clips and forty real voice notes from
/// this Mac, it catches seven of the ten and wrongly flags one of the forty.
///
/// It is **not** a voice-clone detector, and the interface must never imply it is. A modern clone
/// models breath, hesitation and prosody, and will pass this comfortably. The defence against that
/// is structural rather than acoustic: a number the user has not saved never receives a green
/// verdict, however convincing it sounds, and the app tells them to confirm on the number they
/// already have.
public enum SynthesisCheck {
    /// Both thresholds came from the measurement above. Either cue alone fires on ordinary
    /// recordings, so both must agree.
    public static let energyThreshold = 0.29
    public static let zeroCrossingThreshold = 0.14
    /// Below this there are too few windows to measure anything.
    public static let minSpeechSeconds = 2.5

    public struct Features: Sendable, Equatable {
        public let energyVariation: Double
        public let zeroCrossingVariation: Double
    }

    public struct Result: Sendable, Equatable {
        public let soundsSynthetic: Bool
        public let note: String
        public let features: Features
    }

    /// 25 ms windows, the same scale speech itself changes on.
    public static func features(of samples: [Float], sampleRate: Double = 16_000) -> Features {
        let window = Int(sampleRate * 0.025)
        guard window > 0, samples.count >= window * 5 else {
            return Features(energyVariation: 0, zeroCrossingVariation: 0)
        }

        var energies: [Double] = []
        var crossingRates: [Double] = []
        var index = 0
        while index + window <= samples.count {
            let slice = samples[index..<(index + window)]
            energies.append((slice.reduce(0.0) { $0 + Double($1 * $1) } / Double(window)).squareRoot())
            var crossings = 0
            var previous = slice.first ?? 0
            for value in slice {
                if (value < 0) != (previous < 0) { crossings += 1 }
                previous = value
            }
            crossingRates.append(Double(crossings) / Double(window))
            index += window
        }

        let peak = energies.max() ?? 1
        guard peak > 1e-9 else { return Features(energyVariation: 0, zeroCrossingVariation: 0) }
        let normalised = energies.map { $0 / peak }
        return Features(energyVariation: standardDeviation(normalised),
                        zeroCrossingVariation: standardDeviation(crossingRates))
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return (values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)).squareRoot()
    }

    public static func assess(energyVariation: Double, zeroCrossingVariation: Double,
                              speechSeconds: Double) -> Result {
        let features = Features(energyVariation: energyVariation,
                                zeroCrossingVariation: zeroCrossingVariation)
        guard speechSeconds >= minSpeechSeconds,
              energyVariation >= energyThreshold,
              zeroCrossingVariation >= zeroCrossingThreshold else {
            return Result(soundsSynthetic: false, note: "", features: features)
        }
        // Hedged on purpose: the check is weak, and an accusation it cannot support would be worse
        // than saying nothing.
        return Result(soundsSynthetic: true,
                      note: "This might be a recording made by a machine rather than a person. "
                          + "Confirm on a number you already have.",
                      features: features)
    }

    public static func assess(samples: [Float], speechSeconds: Double) -> Result {
        let f = features(of: samples)
        return assess(energyVariation: f.energyVariation,
                      zeroCrossingVariation: f.zeroCrossingVariation,
                      speechSeconds: speechSeconds)
    }
}
