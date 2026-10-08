import Foundation
import QuantTern

/// KotoroCore — the shared brain between the iOS and macOS apps.
///
/// Three jobs: (1) define the local speech-to-text surface, (2) gate access for
/// the freemium model (free ≤ 1 minute; Pro €4.20/month + the beta/WIP anime
/// manuscripts), and (3) turn a transcript into an emotional QuantTern code.

// MARK: - Speech to text

public struct Transcript: Equatable, Sendable {
    public var text: String
    public var seconds: Double
    public var vad: VAD?
    public init(text: String, seconds: Double, vad: VAD? = nil) {
        self.text = text; self.seconds = seconds; self.vad = vad
    }
}

/// Any local, on-device STT engine implements this (Whisper / Parakeet /
/// whatever the device ships). It never leaves the machine.
public protocol SpeechToText: Sendable {
    func transcribe(pcm: [Float], sampleRate: Double) async throws -> Transcript
}

// MARK: - Access (freemium)

public enum Access: Equatable, Sendable {
    case free
    case pro(monthlyEUR: Decimal)
}

public struct Entitlement: Equatable, Sendable {
    /// The unpaid ceiling: one minute of speech-to-text per take.
    public static let freeMaxSeconds: Double = 60
    /// Pro: €4.20 / month, and access to the beta/WIP anime manuscripts.
    public static let proMonthlyEUR: Decimal = 4.20

    public var access: Access
    public init(access: Access = .free) { self.access = access }

    public static let free = Entitlement(access: .free)
    public static func pro() -> Entitlement { Entitlement(access: .pro(monthlyEUR: proMonthlyEUR)) }

    public var isPro: Bool { if case .pro = access { return true }; return false }
    /// The carrot: beta/WIP anime manuscripts are Pro-only.
    public var betaManuscripts: Bool { isPro }

    public func allows(seconds: Double) -> Bool { isPro || seconds <= Self.freeMaxSeconds }
}

public enum KotoroError: Error, Equatable {
    case freeLimitReached(limit: Double)
}

public struct KotoroSession: Sendable {
    public var entitlement: Entitlement
    public var engine: (any SpeechToText)?
    public init(entitlement: Entitlement = .free, engine: (any SpeechToText)? = nil) {
        self.entitlement = entitlement; self.engine = engine
    }

    /// Throws before doing any work if the take would exceed the free ceiling.
    public func check(seconds: Double) throws {
        guard entitlement.allows(seconds: seconds) else {
            throw KotoroError.freeLimitReached(limit: Entitlement.freeMaxSeconds)
        }
    }

    public func transcribe(pcm: [Float], sampleRate: Double, seconds: Double) async throws -> Transcript {
        try check(seconds: seconds)
        guard let engine else { return Transcript(text: "", seconds: seconds) }
        var t = try await engine.transcribe(pcm: pcm, sampleRate: sampleRate)
        t.vad = EmotionTagger().vad(for: t.text)
        return t
    }
}

// MARK: - Emotional QuantTern tagger

/// A tiny, dependency-free VAD tagger used by the demo and the on-device
/// "emotional" pass. A real build layers a learned model on top; the contract
/// (text → VAD → `EmotionCode`) is what matters.
public struct EmotionTagger: Sendable {
    static let positive: Set<String> = ["love", "warm", "hope", "light", "soft", "yes", "thanks", "good", "beautiful", "home", "kind", "gentle"]
    static let negative: Set<String> = ["hate", "cold", "fear", "no", "lost", "broken", "alone", "dark", "sorry", "pain", "never", "tired"]
    static let high: Set<String> = ["wow", "amazing", "hurry", "run", "fire", "now", "go", "yes", "incredible"]

    public init() {}

    public func vad(for text: String) -> VAD {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        guard !words.isEmpty else { return .neutral }
        var v: Float = 0, a: Float = 0
        for w in words {
            if Self.positive.contains(w) { v += 1 }
            if Self.negative.contains(w) { v -= 1 }
            if Self.high.contains(w) { a += 1 }
            if w.hasSuffix("!") { a += 0.5 }
        }
        let n = Float(words.count)
        return VAD(valence: clamp(v / n * 3), arousal: clamp(a / n * 3), dominance: 0)
    }

    public func code(for text: String) -> EmotionCode { QuantTern.encode(vad(for: text)) }

    private func clamp(_ x: Float) -> Float { max(-1, min(1, x)) }
}
