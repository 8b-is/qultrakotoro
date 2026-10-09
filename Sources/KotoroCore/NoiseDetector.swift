import Foundation

/// A cheap, on-device read on the soundscape: how loud the take is right now and
/// roughly what kind of sound it is. Level-only, so it describes the room rather
/// than claiming to tell a voice from a train — useful when you are walking
/// through Tokyo and want to know if the take was clean.
public enum NoiseClass: String, Sendable {
    case silence   // ~nothing
    case quiet     // room tone
    case ambient   // audible background
    case noisy     // loud environment

    public var label: String {
        switch self {
        case .silence: return "silence"
        case .quiet:   return "quiet"
        case .ambient: return "ambient"
        case .noisy:   return "noisy"
        }
    }
}

public struct NoiseProfile: Equatable, Sendable {
    public var levelDBFS: Float          // running RMS, dBFS (≤ 0)
    public var peakDBFS: Float           // loudest sample seen, dBFS (≤ 0)
    public var zeroCrossingRate: Float   // 0…1; higher ≈ more broadband/noisy
    public var classification: NoiseClass

    public init(levelDBFS: Float = -80, peakDBFS: Float = -80,
                zeroCrossingRate: Float = 0, classification: NoiseClass = .silence) {
        self.levelDBFS = levelDBFS
        self.peakDBFS = peakDBFS
        self.zeroCrossingRate = zeroCrossingRate
        self.classification = classification
    }

    public static let silence = NoiseProfile()
}

/// Accumulates a running noise profile from PCM buffers. Deterministic and
/// dependency-free, so it is unit-testable without a microphone.
public struct NoiseDetector {
    /// Smoothing for the running RMS (0…1; higher forgets the past faster).
    public var smoothing: Float
    private var smoothedPower: Float = 0
    private var peak: Float = 0

    public init(smoothing: Float = 0.2) {
        self.smoothing = smoothing
    }

    public private(set) var profile: NoiseProfile = .silence

    @discardableResult
    public mutating func ingest(_ samples: [Float]) -> NoiseProfile {
        guard !samples.isEmpty else { return profile }

        var sumSquares: Float = 0
        var crossings = 0
        var previous = samples[0]
        for s in samples {
            sumSquares += s * s
            if (s >= 0) != (previous >= 0) { crossings += 1 }
            previous = s
        }
        let meanPower = sumSquares / Float(samples.count)
        smoothedPower = smoothing * meanPower + (1 - smoothing) * smoothedPower

        let blockPeak = samples.reduce(Float(0)) { Swift.max($0, abs($1)) }
        peak = Swift.max(peak, blockPeak)

        let level = Self.dBFS(smoothedPower)
        let peakDB = Self.dBFS(peak * peak)
        let zcr = samples.count > 1 ? Float(crossings) / Float(samples.count - 1) : 0

        profile = NoiseProfile(
            levelDBFS: level,
            peakDBFS: peakDB,
            zeroCrossingRate: zcr,
            classification: Self.classify(level: level)
        )
        return profile
    }

    /// Reset the running state (call at the start of a take).
    public mutating func reset() {
        smoothedPower = 0
        peak = 0
        profile = .silence
    }

    private static func dBFS(_ power: Float) -> Float {
        guard power > 0 else { return -80 }
        return Swift.max(-80, 10 * log10(power))
    }

    static func classify(level: Float) -> NoiseClass {
        switch level {
        case ..<(-55): return .silence
        case ..<(-35): return .quiet
        case ..<(-18): return .ambient
        default:       return .noisy
        }
    }
}
