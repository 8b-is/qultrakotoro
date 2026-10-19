import XCTest
@testable import KotoroCore

final class MarineSalienceStreamingTests: XCTestCase {
    private func tone(_ frequency: Double, count: Int = 4096) -> [Float] {
        (0..<count).map {
            0.5 * Float(sin(2 * Double.pi * frequency * Double($0) / 16_000))
        }
    }

    private func feed(_ samples: [Float], chunkSize: Int,
                      into detector: inout MarineSalience) -> Double {
        var total = 0.0
        for start in stride(from: 0, to: samples.count, by: chunkSize) {
            let frame = Array(samples[start..<min(start + chunkSize, samples.count)])
            total += Double(detector.ingest(frame)) * Double(frame.count)
        }
        return total / Double(samples.count)
    }

    func testContiguousSignalIsIndependentOfFrameBoundaries() {
        let samples = tone(200)
        var reference = MarineSalience()
        let referenceScore = feed(samples, chunkSize: samples.count, into: &reference)

        for chunkSize in [1, 16, 64, 256, 1024] {
            var streamed = MarineSalience()
            let score = feed(samples, chunkSize: chunkSize, into: &streamed)
            XCTAssertEqual(streamed.estimatedF0(), reference.estimatedF0(), accuracy: 0.001,
                           "chunk size \(chunkSize)")
            XCTAssertEqual(streamed.emaAmplitude, reference.emaAmplitude, accuracy: 0.000001)
            XCTAssertEqual(score, referenceScore, accuracy: 0.000001)
        }
    }

    func testVoiceAfterInitialSilenceAcquiresFundamental() {
        var detector = MarineSalience()
        _ = detector.ingest([Float](repeating: 0, count: 16_000) + tone(400))
        XCTAssertEqual(detector.estimatedF0(), 400, accuracy: 1)
    }

    func testVoiceAfterSilenceReacquiresChangedFundamental() {
        var detector = MarineSalience()
        _ = detector.ingest(tone(200))
        _ = detector.ingest([Float](repeating: 0, count: 16_000))
        _ = feed(tone(400), chunkSize: 64, into: &detector)
        XCTAssertEqual(detector.estimatedF0(), 400, accuracy: 1)
    }

    func testResetRestoresFreshStreamBehavior() {
        var detector = MarineSalience()
        _ = feed(tone(200), chunkSize: 64, into: &detector)
        detector.reset()
        XCTAssertEqual(detector.estimatedF0(), 0)
        XCTAssertEqual(detector.emaAmplitude, 0)
        var fresh = MarineSalience()
        XCTAssertEqual(detector.ingest(tone(400)), fresh.ingest(tone(400)))
        XCTAssertEqual(detector.estimatedF0(), fresh.estimatedF0())
    }
}
