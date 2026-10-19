import Foundation
import QuantTern

/// 8b-is Dynamic Environment Equalizer (`liquid-rust` +++ `wupz` +++ `qultrakotoro`).
///
/// Unites three sovereign primitives in one deterministic, zero-network loop:
/// 1. **qUltraKotoro** (`NoiseDetector` + `QuantTern`): Measures room soundscape
///    (`levelDBFS`, `peakDBFS`, `zeroCrossingRate`, `NoiseClass`) and quantizes
///    acoustic Valence · Arousal · Dominance into a 4-trit `qt:` tag.
/// 2. **liquid-rust** (`MarineSalience` + Liquid Time-Constant ODE): O(1) peak-to-peak
///    biomechanical salience (`50–640 Hz`) driving a continuous-time LTC ODE
///    (`dx/dt = -[1/τ + |f(I)|]·x + f(I)·A`) across 5 equalizer bands and split-ear
///    transducer compensation (Left Ear 3.5mm Jack + Right Ear AirPods Pro at max headroom).
/// 3. **wupz** (`WupzFrame`): Packs each 32-byte equalizer frame and computes
///    `xor_fold`, `byte_diff`, and `popcount` (matching `wupz_abi.h` ABI v1 bit-for-bit)
///    so CoreAudio hardware registers are only touched when `byte_diff > 0`.

// MARK: - 5-Band Liquid Equalizer Curve

public struct EqBands: Equatable, Codable, Sendable {
    public var sub60Hz: Float       // 60 Hz Sub-bass (dB, -6…+6)
    public var low250Hz: Float      // 250 Hz Warmth / body (dB, -6…+6)
    public var mid1kHz: Float       // 1 kHz Vocal / harmonic core (dB, -6…+6)
    public var highMid4kHz: Float   // 4 kHz Presence / intelligibility (dB, -6…+6)
    public var air12kHz: Float      // 12 kHz Air / Bluetooth shimmer (dB, -6…+6)

    public init(
        sub60Hz: Float = 0,
        low250Hz: Float = 0,
        mid1kHz: Float = 0,
        highMid4kHz: Float = 0,
        air12kHz: Float = 0
    ) {
        self.sub60Hz = Self.clampDB(sub60Hz)
        self.low250Hz = Self.clampDB(low250Hz)
        self.mid1kHz = Self.clampDB(mid1kHz)
        self.highMid4kHz = Self.clampDB(highMid4kHz)
        self.air12kHz = Self.clampDB(air12kHz)
    }

    public static let flat = EqBands()

    public var asArray: [Float] {
        [sub60Hz, low250Hz, mid1kHz, highMid4kHz, air12kHz]
    }

    private static func clampDB(_ x: Float) -> Float {
        Swift.max(-6.0, Swift.min(6.0, x))
    }
}

// MARK: - Split-Ear Routing (Left Ear 3.5mm Jack + Right Ear AirPods Pro)

public struct SplitEarRouting: Equatable, Codable, Sendable {
    public var leftJackVolume: Float        // 0.0…1.0 (1.0 = max headroom)
    public var leftJackPan: Float           // 0.0 = Hard Left
    public var rightAirPodsLeftCh: Float    // 0.0 = Muted Left AirPod
    public var rightAirPodsRightCh: Float   // 0.0…1.0 (1.0 = max headroom Right AirPod)
    public var transducerTrimDB: Float      // Dynamic micro-trim between analog jack & Bluetooth DSP

    public init(
        leftJackVolume: Float = 1.0,
        leftJackPan: Float = 0.0,
        rightAirPodsLeftCh: Float = 0.0,
        rightAirPodsRightCh: Float = 1.0,
        transducerTrimDB: Float = 0.0
    ) {
        self.leftJackVolume = Swift.max(0.0, Swift.min(1.0, leftJackVolume))
        self.leftJackPan = Swift.max(0.0, Swift.min(1.0, leftJackPan))
        self.rightAirPodsLeftCh = Swift.max(0.0, Swift.min(1.0, rightAirPodsLeftCh))
        self.rightAirPodsRightCh = Swift.max(0.0, Swift.min(1.0, rightAirPodsRightCh))
        self.transducerTrimDB = Swift.max(-3.0, Swift.min(3.0, transducerTrimDB))
    }

    public static let maxSplit = SplitEarRouting()
}

// MARK: - Marine Algorithm O(1) Time-Domain Salience (from liquid-rust/src/marine.rs)

public struct MarineSalience: Sendable {
    public var clipThreshold: Float
    public var alpha: Float

    private var prevSample: Float = 0
    private var prevPrevSample: Float = 0
    private var sampleIndex: Int = 0
    private var lastPeakIndex: Int?
    public private(set) var emaAmplitude: Float = 0
    public private(set) var emaPeriod: Float = 0

    public init(clipThreshold: Float = 0.002, alpha: Float = 0.1) {
        self.clipThreshold = clipThreshold
        self.alpha = alpha
    }

    public mutating func reset() {
        prevSample = 0
        prevPrevSample = 0
        sampleIndex = 0
        lastPeakIndex = nil
        emaAmplitude = 0
        emaPeriod = 0
    }

    /// Estimated fundamental frequency F0 in Hz from the tracked peak-to-peak period.
    public func estimatedF0(sampleRate: Float = 16_000) -> Float {
        guard emaPeriod > 0 else { return 0 }
        return sampleRate / emaPeriod
    }

    /// Process a frame of PCM samples and return the mean Marine salience score in `0…1`.
    /// Frames are contiguous parts of one stream; call `reset()` before a new stream.
    /// This is the raw per-sample mean, not a probability or a voice-present threshold.
    /// Above the clip threshold, non-peaks contribute 0.1 times amplitude; valid peaks
    /// contribute 0.4 times amplitude plus 0.6 times inverse jitter. The first peak
    /// anchors timing and receives only the non-peak contribution.
    public mutating func ingest(_ samples: [Float], sampleRate: Float = 16_000) -> Float {
        guard !samples.isEmpty else { return 0 }
        let minPeriod = sampleRate / 640.0 // 640 Hz max human harmonic fundamental
        let maxPeriod = sampleRate / 50.0  // 50 Hz min fundamental

        var totalSalience: Float = 0
        for sample in samples {
            let absSample = abs(sample)
            var salience: Float = 0

            if absSample >= clipThreshold {
                salience = absSample * 0.1
                let isMax = prevPrevSample < prevSample && prevSample > sample
                if isMax {
                    // Peak positions share one clock across every frame boundary.
                    let currentPeak = sampleIndex - 1
                    if let previousPeak = lastPeakIndex {
                        let period = Float(currentPeak - previousPeak)
                        if period >= minPeriod && period <= maxPeriod {
                            let amp = abs(prevSample)
                            if emaPeriod == 0 {
                                emaAmplitude = amp
                                emaPeriod = period
                            } else {
                                emaAmplitude = alpha * amp + (1.0 - alpha) * emaAmplitude
                                emaPeriod = alpha * period + (1.0 - alpha) * emaPeriod
                            }
                            let jP = abs(period - emaPeriod)
                            let jA = abs(amp - emaAmplitude)
                            let jitterContrib = 1.0 / (1.0 + jP + jA)
                            salience = absSample * 0.4 + jitterContrib * 0.6
                            lastPeakIndex = currentPeak
                        } else if period > maxPeriod {
                            // After a gap, measure the next period from this peak.
                            lastPeakIndex = currentPeak
                            emaAmplitude = 0
                            emaPeriod = 0
                        }
                    } else {
                        lastPeakIndex = currentPeak
                    }
                }
            }
            prevPrevSample = prevSample
            prevSample = sample
            sampleIndex += 1
            totalSalience += salience
        }
        return Swift.min(1.0, totalSalience / Float(samples.count))
    }
}

// MARK: - wupz ABI v1 Frame Fold & Incremental Diff (from wupz/wupz-rs/src/fold.rs)

public enum WupzFrame {
    public static let abiVersion: UInt32 = 1
    public static let frameByteCount: Int = 32

    /// Exact little-endian u64 XOR fold matching `wupz_xor_fold` / `xor_fold_scalar`.
    public static func xorFold(_ bytes: [UInt8]) -> UInt64 {
        let fullWordsLen = bytes.count & ~7
        var acc: UInt64 = 0
        var i = 0
        while i < fullWordsLen {
            acc ^= UInt64(bytes[i]) << UInt64((i & 7) * 8)
            i += 1
        }
        while i < bytes.count {
            acc ^= UInt64(bytes[i])
            i += 1
        }
        return acc
    }

    /// Number of differing bytes between two equal-length frames (`wupz_byte_diff`).
    public static func byteDiff(_ a: [UInt8], _ b: [UInt8]) -> UInt64 {
        let n = Swift.min(a.count, b.count)
        var diff: UInt64 = 0
        for i in 0..<n where a[i] != b[i] {
            diff += 1
        }
        return diff
    }

    /// Bit population count across the packed frame (`wupz_popcount`).
    public static func popcount(_ bytes: [UInt8]) -> UInt64 {
        bytes.reduce(0) { $0 + UInt64($1.nonzeroBitCount) }
    }

    /// Deterministically pack a 32-byte equalizer state frame (quantized to centi-dB / milli-units)
    /// so tiny floating-point noise does not trigger spurious hardware updates.
    public static func packFrame(
        noise: NoiseProfile,
        salience: Float,
        bands: EqBands,
        splitEar: SplitEarRouting,
        emotion: EmotionCode
    ) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: frameByteCount)
        func putI16(_ offset: Int, _ val: Float, scale: Float) {
            let q = Int16(clamping: Int((val * scale).rounded()))
            let u = UInt16(bitPattern: q)
            out[offset] = UInt8(u & 0xff)
            out[offset + 1] = UInt8((u >> 8) & 0xff)
        }
        putI16(0,  noise.levelDBFS, scale: 10.0)          // 0..1: level (0.1 dB steps)
        putI16(2,  noise.peakDBFS, scale: 10.0)           // 2..3: peak (0.1 dB steps)
        putI16(4,  noise.zeroCrossingRate, scale: 1000.0) // 4..5: ZCR (0.001 steps)
        putI16(6,  salience, scale: 1000.0)               // 6..7: Marine salience
        putI16(8,  bands.sub60Hz, scale: 100.0)           // 8..9: 60 Hz (0.01 dB)
        putI16(10, bands.low250Hz, scale: 100.0)          // 10..11: 250 Hz
        putI16(12, bands.mid1kHz, scale: 100.0)           // 12..13: 1 kHz
        putI16(14, bands.highMid4kHz, scale: 100.0)       // 14..15: 4 kHz
        putI16(16, bands.air12kHz, scale: 100.0)          // 16..17: 12 kHz
        putI16(18, splitEar.leftJackVolume, scale: 1000.0)
        putI16(20, splitEar.rightAirPodsRightCh, scale: 1000.0)
        putI16(22, splitEar.transducerTrimDB, scale: 100.0)
        out[24] = emotion.bytes.first ?? 0b01010101
        out[25] = UInt8(WupzFrame.abiVersion & 0xff)
        // 26..31: XOR checksum witness prefix over bytes 0..25
        let foldPrefix = xorFold(Array(out[0..<26]))
        for k in 0..<6 {
            out[26 + k] = UInt8((foldPrefix >> UInt64(k * 8)) & 0xff)
        }
        return out
    }
}

// MARK: - Dynamic Equalizer Snapshot & Engine

public struct DynamicEqSnapshot: Equatable, Sendable {
    public var noise: NoiseProfile
    public var salience: Float
    public var estimatedF0Hz: Float
    public var vad: VAD
    public var emotion: EmotionCode
    public var bands: EqBands
    public var splitEar: SplitEarRouting
    public var wupzFold: UInt64
    public var wupzByteDiff: UInt64
    public var wupzPopcount: UInt64
    public var frameBytes: [UInt8]

    public var requiresHardwareUpdate: Bool { wupzByteDiff > 0 }
}

/// Liquid Time-Constant (LTC) Dynamic Environment Equalizer.
public struct DynamicEqualizer: Sendable {
    public var noiseDetector: NoiseDetector
    public var marineDetector: MarineSalience
    public var maxVolume: Bool

    /// Base time constants τ (in frames) for the 5 bands:
    /// Sub-bass adapts slowly; Mid/Presence adapts rapidly to vocal salience.
    private let tau: [Float] = [4.0, 3.5, 1.8, 1.5, 2.2]
    private var state: [Float] = [0, 0, 0, 0, 0]
    private var prevFrame: [UInt8] = [UInt8](repeating: 0, count: WupzFrame.frameByteCount)

    public private(set) var lastSnapshot: DynamicEqSnapshot?

    public init(maxVolume: Bool = true, smoothing: Float = 0.25) {
        self.noiseDetector = NoiseDetector(smoothing: smoothing)
        self.marineDetector = MarineSalience()
        self.maxVolume = maxVolume
    }

    public mutating func reset() {
        noiseDetector.reset()
        marineDetector.reset()
        state = [0, 0, 0, 0, 0]
        prevFrame = [UInt8](repeating: 0, count: WupzFrame.frameByteCount)
        lastSnapshot = nil
    }

    /// Ingest a PCM audio buffer from the environment microphone and compute the
    /// next Liquid Time-Constant EQ curve, Split-Ear routing, QuantTern code, and wupz witness.
    @discardableResult
    public mutating func ingest(_ samples: [Float], sampleRate: Float = 16_000) -> DynamicEqSnapshot {
        let noise = noiseDetector.ingest(samples)
        let salience = marineDetector.ingest(samples, sampleRate: sampleRate)
        let f0 = marineDetector.estimatedF0(sampleRate: sampleRate)

        // Normalize acoustic features into [-1, +1] for VAD & LTC ODE drive
        // Normalized room loudness: -80 dBFS -> 0.0, 0 dBFS -> 1.0
        let loudnessNorm = Swift.max(0.0, Swift.min(1.0, (noise.levelDBFS + 80.0) / 80.0))
        let zcr = Swift.max(0.0, Swift.min(1.0, noise.zeroCrossingRate))
        let salNorm = Swift.max(0.0, Swift.min(1.0, salience * 4.0))

        // Acoustic VAD -> QuantTern 4-trit code:
        // - Valence: harmonic warmth & vocal salience vs harsh broadband ZCR
        // - Arousal: ambient energy level (dBFS)
        // - Dominance: peak transient authority & Marine harmonic lock
        let valence = Swift.max(-1.0, Swift.min(1.0, (salNorm * 1.4) - (zcr * 1.2) + 0.2))
        let arousal = Swift.max(-1.0, Swift.min(1.0, (loudnessNorm * 2.0) - 1.0))
        let dominance = Swift.max(-1.0, Swift.min(1.0, (salNorm * 1.5) + ((noise.peakDBFS + 40.0) / 40.0) * 0.5 - 0.3))
        let vad = VAD(valence: valence, arousal: arousal, dominance: dominance)
        let emotion = QuantTern.encode(vad)

        // Compute target EQ gains A_b (in dB) for the 5 bands based on environment class + Marine salience:
        // 1. 60 Hz Sub-bass: rich foundation in quiet/silence (+2.2 dB) or punchy compensation in noisy rooms (+3.5 dB)
        // 2. 250 Hz Warmth: warm in quiet (+1.5 dB), de-mudded in noisy low-ZCR rumble (-1.8 dB)
        // 3. 1 kHz Vocal Core: driven by liquid-rust Marine salience (+0.5 to +3.8 dB)
        // 4. 4 kHz Presence: articulation lift in ambient/noisy environments (+1.0 to +4.2 dB), gentle in high-ZCR hiss
        // 5. 12 kHz Air: crystalline highs compensating Bluetooth AirPods roll-off vs Left 3.5mm jack (+1.8 to +3.2 dB)
        let targets: [Float]
        switch noise.classification {
        case .silence:
            targets = [
                +2.4,                                   // 60 Hz Fletcher-Munson sub warmth
                +1.6,                                   // 250 Hz intimate body
                +0.6 + salNorm * 1.5,                   // 1 kHz natural center
                +0.4,                                   // 4 kHz relaxed presence
                +2.0                                    // 12 kHz open air
            ]
        case .quiet:
            targets = [
                +2.0,
                +1.2 - zcr * 0.8,
                +1.2 + salNorm * 2.0,
                +1.0 + salNorm * 1.2,
                +2.2
            ]
        case .ambient:
            targets = [
                +2.8,
                -0.8 + salNorm * 0.6,                   // cut room boxiness at 250 Hz
                +2.0 + salNorm * 2.2,                   // lift harmonic core
                +2.4 - zcr * 1.0,                       // clear presence without sibilance
                +2.6
            ]
        case .noisy:
            targets = [
                +3.6,                                   // overcome low-end environmental masking
                -2.0,                                   // carve out muddy 250 Hz room resonance
                +2.8 + salNorm * 2.4,                   // lock onto harmonic voice/music core
                +3.4 - zcr * 1.2,                       // high articulation cut-through
                +3.0                                    // preserve air at max volume
            ]
        }

        // Liquid Time-Constant (LTC) continuous-time ODE integration step (dt = 1 frame):
        // dx/dt = -(1/τ + |f(I)|) * x + f(I) * A
        // Exact exponential-Euler step guarantees stability for any input drive |f(I)|.
        let drive = 0.35 + 0.65 * Swift.max(loudnessNorm, salNorm)
        for b in 0..<5 {
            let rate = (1.0 / tau[b]) + drive
            let decay = exp(-rate)
            let asymptotic = (drive / rate) * targets[b]
            state[b] = state[b] * decay + asymptotic * (1.0 - decay)
        }

        let bands = EqBands(
            sub60Hz: state[0],
            low250Hz: state[1],
            mid1kHz: state[2],
            highMid4kHz: state[3],
            air12kHz: state[4]
        )

        // Asymmetric transducer trim between Left Ear (3.5mm Analog Jack) and Right Ear (AirPods Pro)
        let trimDB = (bands.air12kHz - bands.sub60Hz) * 0.25
        let baseVol: Float = maxVolume ? 1.0 : Swift.max(0.65, Swift.min(1.0, 0.70 + loudnessNorm * 0.30))
        let splitEar = SplitEarRouting(
            leftJackVolume: baseVol,
            leftJackPan: 0.0,
            rightAirPodsLeftCh: 0.0,
            rightAirPodsRightCh: baseVol,
            transducerTrimDB: trimDB
        )

        let frame = WupzFrame.packFrame(
            noise: noise,
            salience: salience,
            bands: bands,
            splitEar: splitEar,
            emotion: emotion
        )
        let fold = WupzFrame.xorFold(frame)
        let diff = WupzFrame.byteDiff(frame, prevFrame)
        let pop = WupzFrame.popcount(frame)
        prevFrame = frame

        let snap = DynamicEqSnapshot(
            noise: noise,
            salience: salience,
            estimatedF0Hz: f0,
            vad: vad,
            emotion: emotion,
            bands: bands,
            splitEar: splitEar,
            wupzFold: fold,
            wupzByteDiff: diff,
            wupzPopcount: pop,
            frameBytes: frame
        )
        lastSnapshot = snap
        return snap
    }
}
