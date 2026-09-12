import Foundation

/// Float-vector helpers for 256-d speaker embeddings.
public enum Vector {
    /// Cosine similarity. Returns 0 for empty, mismatched, or zero-magnitude input.
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    public static func normalized(_ v: [Float]) -> [Float] {
        let norm = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }

    /// L2-normalised mean of the vectors. Empty input yields an empty vector.
    public static func centroid(_ vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first else { return [] }
        var sum = [Float](repeating: 0, count: first.count)
        for v in vectors where v.count == first.count {
            for i in 0..<v.count { sum[i] += v[i] }
        }
        return normalized(sum.map { $0 / Float(vectors.count) })
    }

    public static func toData(_ v: [Float]) -> Data {
        v.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public static func fromData(_ d: Data) -> [Float] {
        let count = d.count / MemoryLayout<Float>.size
        guard count > 0 else { return [] }
        return d.withUnsafeBytes { raw in
            Array(UnsafeBufferPointer(start: raw.bindMemory(to: Float.self).baseAddress, count: count))
        }
    }
}
