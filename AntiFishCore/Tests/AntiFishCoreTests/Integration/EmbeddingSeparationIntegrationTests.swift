import XCTest
@testable import AntiFishCore

/// Guards the scoring decision on this Mac's real speakers, and prints the numbers behind it.
/// Raw cosine barely separates voices because the embedding space carries a large shared
/// component; centering removes it. This test fails if that stops being true.
final class EmbeddingSeparationIntegrationTests: XCTestCase {
    func testCenteringSeparatesRealSpeakersBetterThanRawCosine() async throws {
        try TestEnv.skipUnlessRealWA()
        try TestEnv.skipUnlessModels()

        let locator = ContainerLocator()
        let store = try ChatStore.open(url: locator.chatStorageURL)
        let notes = try VoiceNoteQuery.fetch(store).filter {
            !$0.isFromMe && !$0.senderJID.isEmpty && !$0.senderJID.hasPrefix("status@")
                && $0.durationSeconds >= 4
                && FileManager.default.fileExists(atPath: locator.mediaURL(relativePath: $0.relativeMediaPath).path)
        }
        let bySender = Dictionary(grouping: notes, by: \.senderJID).filter { $0.value.count >= 6 }
        let senders = Array(bySender.keys.sorted().prefix(10))
        print("SEPARATION senders=\(senders.count)")

        let engine = try VoiceEngine(models: ModelPaths(directory: TestEnv.modelsDir), numThreads: 4)
        var embeddings: [String: [[Float]]] = [:]
        var speech: [String: [Double]] = [:]
        var isGroup: [String: Bool] = [:]
        for sender in senders {
            for note in bySender[sender]!.suffix(10) {
                let a = try await engine.analyze(url: locator.mediaURL(relativePath: note.relativeMediaPath))
                if !a.embedding.isEmpty, a.speechSeconds >= 2 {
                    embeddings[sender, default: []].append(a.embedding)
                    speech[sender, default: []].append(a.speechSeconds)
                    isGroup[sender] = note.chatIsGroup
                }
            }
        }
        let usable = embeddings.filter { $0.value.count >= 3 }
        print("SEPARATION usable senders=\(usable.count) total notes=\(usable.values.map(\.count).reduce(0,+))")
        try XCTSkipUnless(usable.count >= 3, "not enough speakers with usable audio")

        let all = usable.values.flatMap { $0 }
        var mean = [Float](repeating: 0, count: all[0].count)
        for v in all { for i in 0..<v.count { mean[i] += v[i] / Float(all.count) } }

        var gaps: [String: Float] = [:]

        func report(_ label: String, _ transform: ([Float]) -> [Float]) {
            let t = usable.mapValues { $0.map(transform) }
            var same: [Float] = [], diff: [Float] = []
            for (sender, vectors) in t {
                for i in 0..<vectors.count {
                    for j in (i + 1)..<vectors.count { same.append(Vector.cosine(vectors[i], vectors[j])) }
                    for (other, otherVectors) in t where other != sender {
                        for ov in otherVectors { diff.append(Vector.cosine(vectors[i], ov)) }
                    }
                }
            }
            let sm = same.reduce(0,+) / Float(same.count)
            let dm = diff.reduce(0,+) / Float(diff.count)
            let sSorted = same.sorted(), dSorted = diff.sorted()
            let gen2 = sSorted[max(0, Int(0.02 * Double(sSorted.count - 1)))]
            let imp99 = dSorted[Int(0.99 * Double(dSorted.count - 1))]
            gaps[label] = sm - dm
            print(String(format: "SEPARATION %-22@ sameMean=%.3f diffMean=%.3f gap=%.3f  gen2=%.3f imp99=%.3f pairs(same=%d diff=%d)",
                         label, sm, dm, sm - dm, gen2, imp99, same.count, diff.count))
        }

        report("note-note raw") { $0 }
        report("note-note centered") { EmbeddingCenter(mean: mean).project($0) }

        // What the product actually does: score one note against a centroid built from the rest of
        // that speaker's notes (leave-one-out), and against every other speaker's full centroid.
        func reportCentroid(_ label: String, _ transform: ([Float]) -> [Float]) {
            let t = usable.mapValues { $0.map(transform) }
            let centroids = t.mapValues { Vector.centroid($0) }
            var same: [Float] = [], diff: [Float] = []
            for (sender, vectors) in t {
                for i in 0..<vectors.count {
                    var rest = vectors
                    rest.remove(at: i)
                    same.append(Vector.cosine(vectors[i], Vector.centroid(rest)))
                    for (other, centroid) in centroids where other != sender {
                        diff.append(Vector.cosine(vectors[i], centroid))
                    }
                }
            }
            let sm = same.reduce(0,+) / Float(same.count)
            let dm = diff.reduce(0,+) / Float(diff.count)
            let sSorted = same.sorted(), dSorted = diff.sorted()
            let gen2 = sSorted[max(0, Int(0.02 * Double(sSorted.count - 1)))]
            let imp99 = dSorted[Int(0.99 * Double(dSorted.count - 1))]
            let errors = same.filter { $0 <= imp99 }.count
            gaps[label] = sm - dm
            print(String(format: "SEPARATION %-22@ sameMean=%.3f diffMean=%.3f gap=%.3f  gen2=%.3f imp99=%.3f genuineBelowImp99=%d/%d",
                         label, sm, dm, sm - dm, gen2, imp99, errors, same.count))
        }

        let center = EmbeddingCenter(mean: mean)
        reportCentroid("centroid raw") { $0 }
        reportCentroid("centroid centered") { center.project($0) }

        // Per-speaker breakdown under the best scheme, to see whether weak separation is uniform
        // or caused by a few noisy speakers (group chats often carry forwarded or mixed audio).
        let centeredBySender = usable.mapValues { $0.map(center.project) }
        let centroids = centeredBySender.mapValues { Vector.centroid($0) }
        for (sender, vectors) in centeredBySender.sorted(by: { $0.key < $1.key }) {
            var loo: [Float] = []
            for i in 0..<vectors.count {
                var rest = vectors; rest.remove(at: i)
                loo.append(Vector.cosine(vectors[i], Vector.centroid(rest)))
            }
            let best = centroids.filter { $0.key != sender }
                .map { Vector.cosine(Vector.centroid(vectors), $0.value) }.max() ?? 0
            let meanSpeech = (speech[sender] ?? []).reduce(0,+) / Double(max(1, (speech[sender] ?? []).count))
            print(String(format: "SEPARATION   sender#%02d notes=%2d group=%@ speech=%.1fs looMin=%.3f looMean=%.3f bestOther=%.3f",
                         abs(sender.hashValue) % 100, vectors.count, (isGroup[sender] ?? false) ? "y" : "n",
                         meanSpeech, loo.min() ?? 0, loo.reduce(0,+) / Float(loo.count), best))
        }

        let rawGap = try XCTUnwrap(gaps["centroid raw"])
        let centeredGap = try XCTUnwrap(gaps["centroid centered"])
        XCTAssertGreaterThan(centeredGap, rawGap,
                             "centering should separate voices better than raw cosine")
        XCTAssertGreaterThan(centeredGap, 0.3,
                             "centred same-speaker and different-speaker scores must be clearly apart")
        XCTAssertGreaterThan(try XCTUnwrap(gaps["note-note centered"]), try XCTUnwrap(gaps["note-note raw"]))
    }
}
