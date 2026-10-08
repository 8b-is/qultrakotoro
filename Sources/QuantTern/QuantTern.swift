import Foundation

/// QuantTern — an *emotional* ternary encoding.
///
/// The VAD model of emotion (Valence · Arousal · Dominance, each −1…+1) is
/// quantized to a **ternary** vector `{-1, 0, +1}` and packed two bits per
/// trit — the same 1.58-bit idea BitNet b1.58 uses for weights, applied to
/// feeling instead of parameters. The result is a tiny, honest fingerprint of
/// affect: cheap to store, cheap to compare, and it cannot lie about *how much*
/// it is sure (a `zero` is a real "don't know").
public struct VAD: Equatable, Codable, Sendable {
    public var valence: Float    // −1 unpleasant … +1 pleasant
    public var arousal: Float    // −1 calm … +1 excited
    public var dominance: Float  // −1 controlled … +1 in control

    public init(valence: Float, arousal: Float, dominance: Float) {
        self.valence = max(-1, min(1, valence))
        self.arousal = max(-1, min(1, arousal))
        self.dominance = max(-1, min(1, dominance))
    }

    public static let neutral = VAD(valence: 0, arousal: 0, dominance: 0)
    public var trits: [Trit] { [valence, arousal, dominance].map { Trit($0) } }
}

public enum Trit: Int8, Codable, Sendable, CaseIterable {
    case minus = -1, zero = 0, plus = 1

    public init(_ x: Float, threshold: Float = QuantTern.defaultThreshold) {
        if x >= threshold { self = .plus }
        else if x <= -threshold { self = .minus }
        else { self = .zero }
    }
}

/// A packed emotional code: the trits, the bytes, and a printable `qt:` hex tag.
public struct EmotionCode: Equatable, Codable, Sendable {
    public let trits: [Trit]
    public let bytes: [UInt8]
    public let hex: String

    /// How many trits are non-neutral — the "signal" in the fingerprint.
    public var magnitude: Int { trits.reduce(0) { $0 + ($1 == .zero ? 0 : 1) } }
    public var isNeutral: Bool { magnitude == 0 }

    public init(trits: [Trit], bytes: [UInt8], hex: String) {
        self.trits = trits; self.bytes = bytes; self.hex = hex
    }
}

public enum QuantTern {
    /// Default ternary threshold. Below this the value reads as a genuine "0".
    public static let defaultThreshold: Float = 0.33

    public static func encode(_ vad: VAD, threshold: Float = defaultThreshold) -> EmotionCode {
        pack(vad.trits)
    }

    public static func pack(_ trits: [Trit]) -> EmotionCode {
        var bytes: [UInt8] = []
        var i = 0
        while i < trits.count {
            var b: UInt8 = 0
            for j in 0..<4 {
                let t: Trit = (i + j) < trits.count ? trits[i + j] : .zero
                let code = UInt8((Int(t.rawValue) + 1) & 0b11) // −1→0, 0→1, +1→2
                b |= code << UInt8(2 * j)
            }
            bytes.append(b)
            i += 4
        }
        let hex = "qt:" + bytes.map { String(format: "%02x", $0) }.joined()
        return EmotionCode(trits: trits, bytes: bytes, hex: hex)
    }

    public static func unpack(_ bytes: [UInt8], count: Int) -> [Trit] {
        var trits: [Trit] = []
        for b in bytes {
            for j in 0..<4 {
                let code = Int((b >> UInt8(2 * j)) & 0b11)
                trits.append(Trit(rawValue: Int8(code - 1)) ?? .zero)
            }
        }
        return Array(trits.prefix(count))
    }

    /// Cosine-style agreement in {0…1}: how alike two emotional codes are.
    public static func agreement(_ a: [Trit], _ b: [Trit]) -> Float {
        let n = min(a.count, b.count)
        guard n > 0 else { return 1 }
        var hit = 0
        for i in 0..<n where a[i] == b[i] { hit += 1 }
        return Float(hit) / Float(n)
    }
}
