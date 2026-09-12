import XCTest
@testable import AntiFishCore

/// A second look at a voice note: does it sound machine-made at all?
///
/// This is not a voice-clone detector and must not be presented as one. It measures two crude
/// tells — loudness that varies too evenly, and a spectrum that flips too regularly. Measured
/// against ten synthesised clips and forty real voice notes from this Mac it catches seven of the
/// ten and wrongly flags one of the forty. A modern clone models breath and prosody, so it will
/// pass this comfortably. The defence against that is elsewhere: an unsaved number never gets a
/// green verdict, whatever it sounds like.
final class SynthesisCheckTests: XCTestCase {

    func testSteadyLoudnessAndRegularSpectrumReadAsSynthetic() {
        let result = SynthesisCheck.assess(energyVariation: 0.31, zeroCrossingVariation: 0.16,
                                           speechSeconds: 5)
        XCTAssertTrue(result.soundsSynthetic)
        XCTAssertFalse(result.note.isEmpty)
    }

    func testHumanSpeechIsLeftAlone() {
        let result = SynthesisCheck.assess(energyVariation: 0.19, zeroCrossingVariation: 0.08,
                                           speechSeconds: 9)
        XCTAssertFalse(result.soundsSynthetic)
        XCTAssertTrue(result.note.isEmpty)
    }

    /// Both cues have to agree. Either alone fires on ordinary recordings.
    func testOneCueAloneIsNotEnough() {
        XCTAssertFalse(SynthesisCheck.assess(energyVariation: 0.31, zeroCrossingVariation: 0.05,
                                             speechSeconds: 5).soundsSynthetic)
        XCTAssertFalse(SynthesisCheck.assess(energyVariation: 0.10, zeroCrossingVariation: 0.16,
                                             speechSeconds: 5).soundsSynthetic)
    }

    /// A two-second clip has too few windows to measure anything reliably.
    func testTooShortToJudge() {
        let result = SynthesisCheck.assess(energyVariation: 0.31, zeroCrossingVariation: 0.16,
                                           speechSeconds: 1.5)
        XCTAssertFalse(result.soundsSynthetic)
    }

    /// The wording has to be a suggestion, not an accusation, because the check is weak.
    func testTheNoteHedgesRatherThanAccuses() {
        let note = SynthesisCheck.assess(energyVariation: 0.31, zeroCrossingVariation: 0.16,
                                         speechSeconds: 5).note
        XCTAssertTrue(note.lowercased().contains("might"), note)
        XCTAssertFalse(note.contains("_"))
    }

    func testFeaturesComeOutOfRealSamples() {
        // A pure tone has near-constant loudness and a perfectly regular spectrum, which is the
        // extreme version of what synthesis looks like.
        let tone = (0..<16_000).map { Float(sin(Double($0) * 0.2)) * 0.5 }
        let f = SynthesisCheck.features(of: tone)
        XCTAssertLessThan(f.energyVariation, 0.1, "a steady tone barely varies in loudness")

        // A sweep from low to high pitch changes how often the waveform crosses zero, which is
        // exactly what the second cue measures.
        let sweep = (0..<16_000).map { i -> Float in
            let t = Double(i) / 16_000
            return Float(sin(2 * .pi * (200 + 3_000 * t) * t)) * 0.5
        }
        XCTAssertGreaterThan(SynthesisCheck.features(of: sweep).zeroCrossingVariation, 0.01)
    }

    func testSilenceProducesNothing() {
        let f = SynthesisCheck.features(of: [Float](repeating: 0, count: 16_000))
        XCTAssertEqual(f.energyVariation, 0, accuracy: 1e-6)
    }
}
