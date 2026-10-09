import XCTest
@testable import QuantTern
@testable import KotoroCore

final class QuantTernTests: XCTestCase {

    func testTritThresholds() {
        XCTAssertEqual(Trit(0.9), .plus)
        XCTAssertEqual(Trit(-0.9), .minus)
        XCTAssertEqual(Trit(0.1), .zero)          // a real "don't know"
        XCTAssertEqual(Trit(0.33), .plus)         // boundary is inclusive
    }

    func testPackRoundTrip() {
        let trits: [Trit] = [.plus, .zero, .minus, .plus, .minus, .zero, .zero, .plus, .minus]
        let code = QuantTern.pack(trits)
        XCTAssertEqual(code.bytes.count, 3)       // 9 trits → 3 bytes (4 per byte, zero-padded)
        XCTAssertTrue(code.hex.hasPrefix("qt:"))
        XCTAssertEqual(QuantTern.unpack(code.bytes, count: trits.count), trits)
    }

    func testEncodeNeutralIsZero() {
        let code = QuantTern.encode(.neutral)
        XCTAssertTrue(code.isNeutral)
        XCTAssertEqual(code.magnitude, 0)
        XCTAssertEqual(code.bytes, [0b01010101])  // every trit = zero (code 1)
    }

    func testEncodeCustomHigherThreshold() {
        let code = QuantTern.encode(
            VAD(valence: 0.6, arousal: -0.6, dominance: 0.4), threshold: 0.75
        )
        XCTAssertEqual(code.trits, [.zero, .zero, .zero])
        XCTAssertEqual(code.bytes, [0b01010101])
    }

    func testEncodeCustomLowerThreshold() {
        let code = QuantTern.encode(
            VAD(valence: 0.2, arousal: -0.2, dominance: 0.09), threshold: 0.1
        )
        XCTAssertEqual(code.trits, [.plus, .minus, .zero])
        XCTAssertEqual(code.bytes, [0b01010010])
    }

    func testEncodeCustomThresholdIsInclusive() {
        let code = QuantTern.encode(
            VAD(valence: 0.5, arousal: -0.5, dominance: 0.49), threshold: 0.5
        )
        XCTAssertEqual(code.trits, [.plus, .minus, .zero])
    }

    func testEncodeDefaultThresholdPreservesPacking() {
        let vad = VAD(valence: 0.33, arousal: -0.33, dominance: 0.32)
        let code = QuantTern.encode(vad)
        XCTAssertEqual(code.trits, [.plus, .minus, .zero])
        XCTAssertEqual(code.bytes, [0b01010010])
        XCTAssertEqual(code.hex, "qt:52")
        XCTAssertEqual(code, QuantTern.encode(vad, threshold: QuantTern.defaultThreshold))
    }

    func testEncodePositiveWords() {
        let tagger = EmotionTagger()
        let v = tagger.vad(for: "I love this warm good hope")
        XCTAssertGreaterThan(v.valence, 0.5)
        let code = tagger.code(for: "I love this warm good hope")
        XCTAssertEqual(code.trits.first, .plus)   // valence trit fires
    }

    func testAgreementIdentity() {
        let a = QuantTern.encode(VAD(valence: 0.8, arousal: 0.5, dominance: 0)).trits
        XCTAssertEqual(QuantTern.agreement(a, a), 1.0)
    }
}

final class AccessTests: XCTestCase {

    func testFreeCeiling() {
        let e = Entitlement.free
        XCTAssertTrue(e.allows(seconds: 60))
        XCTAssertFalse(e.allows(seconds: 60.1))
        XCTAssertFalse(e.isPro)
        XCTAssertFalse(e.betaManuscripts)
    }

    func testProIsUnlimitedAndGetsManuscripts() {
        let e = Entitlement.pro()
        XCTAssertTrue(e.isPro)
        XCTAssertTrue(e.allows(seconds: 3600))
        XCTAssertTrue(e.betaManuscripts)
        XCTAssertEqual(Entitlement.proMonthlyEUR, Decimal(string: "4.20"))
    }

    func testSessionThrowsOverFreeLimit() {
        let s = KotoroSession(entitlement: .free)
        XCTAssertNoThrow(try s.check(seconds: 30))
        XCTAssertThrowsError(try s.check(seconds: 61)) { err in
            XCTAssertEqual(err as? KotoroError, .freeLimitReached(limit: 60))
        }
    }
}

final class TakeFlowTests: XCTestCase {

    func testDemoEngineMeasuresDurationFromPCM() async throws {
        let engine = OfflineDemoEngine(text: "hello there")
        let pcm = TakeAudio.take(seconds: 30)
        XCTAssertEqual(pcm.count, 30 * 16_000)
        let t = try await engine.transcribe(pcm: pcm, sampleRate: TakeAudio.defaultSampleRate)
        XCTAssertEqual(t.seconds, 30, accuracy: 0.001)
        XCTAssertEqual(t.text, "hello there")
    }

    func testSessionTagsEmotionEndToEnd() async throws {
        let session = KotoroSession(entitlement: .pro(),
                                    engine: OfflineDemoEngine(text: "I love this warm good hope"))
        let t = try await session.transcribe(pcm: TakeAudio.take(seconds: 5),
                                             sampleRate: TakeAudio.defaultSampleRate,
                                             seconds: 5)
        let vad = try XCTUnwrap(t.vad)
        XCTAssertGreaterThan(vad.valence, 0.5)
        XCTAssertTrue(QuantTern.encode(vad).hex.hasPrefix("qt:"))
    }

    func testSessionGatesBeforeEngineRuns() async {
        let session = KotoroSession(entitlement: .free,
                                    engine: OfflineDemoEngine(text: "too long"))
        do {
            _ = try await session.transcribe(pcm: TakeAudio.take(seconds: 90),
                                             sampleRate: TakeAudio.defaultSampleRate,
                                             seconds: 90)
            XCTFail("expected the free gate to reject a 90 s take")
        } catch let error as KotoroError {
            XCTAssertEqual(error, .freeLimitReached(limit: 60))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

final class NoiseDetectorTests: XCTestCase {

    private func sine(amplitude: Float, count: Int = 4096) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * Double.pi * 440 * Double($0) / 16_000)) }
    }

    func testSilenceClassifiesSilent() {
        var detector = NoiseDetector()
        let profile = detector.ingest([Float](repeating: 0, count: 2048))
        XCTAssertEqual(profile.classification, .silence)
        XCTAssertEqual(profile.levelDBFS, -80, accuracy: 0.001)
    }

    func testFullScaleToneIsNoisy() {
        var detector = NoiseDetector()
        for _ in 0..<30 { _ = detector.ingest(sine(amplitude: 1.0)) }
        // full-scale sine RMS ≈ 0.707 → ≈ −3 dBFS
        XCTAssertEqual(detector.profile.levelDBFS, -3.0, accuracy: 1.0)
        XCTAssertEqual(detector.profile.classification, .noisy)
        XCTAssertEqual(detector.profile.peakDBFS, 0, accuracy: 0.5)
    }

    func testQuietToneIsQuiet() {
        var detector = NoiseDetector()
        for _ in 0..<30 { _ = detector.ingest(sine(amplitude: 0.02)) }
        XCTAssertEqual(detector.profile.classification, .quiet)
    }

    func testResetClearsState() {
        var detector = NoiseDetector()
        for _ in 0..<10 { _ = detector.ingest(sine(amplitude: 1.0)) }
        detector.reset()
        XCTAssertEqual(detector.profile, .silence)
    }
}
