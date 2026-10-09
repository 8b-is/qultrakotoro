import XCTest
import Speech
@testable import KotoroCore

final class LocalSpeechTests: XCTestCase {
    func testUnsupportedLocalModelFailsEvenWhenServiceIsAvailable() {
        XCTAssertThrowsError(try LocalSpeechPolicy.validate(available: true, supportsOnDevice: false)) {
            XCTAssertEqual($0 as? LocalSpeechError, .onDeviceUnsupported)
        }
        XCTAssertThrowsError(try LocalSpeechPolicy.validate(available: false, supportsOnDevice: true))
        XCTAssertNoThrow(try LocalSpeechPolicy.validate(available: true, supportsOnDevice: true))
    }

    func testPreparedRequestAlwaysRequiresLocalRecognition() throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        try LocalSpeechPolicy.prepare(request, available: true, supportsOnDevice: true)
        XCTAssertTrue(request.requiresOnDeviceRecognition)
        XCTAssertThrowsError(try LocalSpeechPolicy.prepare(request, available: true, supportsOnDevice: false))
        XCTAssertTrue(request.requiresOnDeviceRecognition)
    }

    @MainActor func testPartialDoesNotCompleteAndLateFinalIsPreserved() async throws {
        let result = LocalSpeechResult()
        result.receive(text: "early words", isFinal: false, error: nil)
        let waiting = Task { try await result.wait() }
        await Task.yield()
        result.receive(text: "early words and final words", isFinal: true, error: nil)
        let text = try await waiting.value
        XCTAssertEqual(text, "early words and final words")
        // Duplicate framework completion must neither resume twice nor replace it.
        result.receive(text: nil, isFinal: false, error: LocalSpeechError.unavailable)
        let retained = try await result.wait()
        XCTAssertEqual(retained, text)
    }

    @MainActor func testErrorIsNotReportedAsEmptySuccessfulTranscript() async {
        let result = LocalSpeechResult()
        result.receive(text: nil, isFinal: false, error: LocalSpeechError.unavailable)
        do { _ = try await result.wait(); XCTFail("expected failure") }
        catch { XCTAssertEqual(error as? LocalSpeechError, .unavailable) }
    }

    @MainActor func testMissingFinalTimesOutInsteadOfReturningPartial() async {
        let result = LocalSpeechResult()
        result.receive(text: "partial", isFinal: false, error: nil)
        do { _ = try await result.wait(timeoutNanoseconds: 1_000_000); XCTFail("expected timeout") }
        catch { XCTAssertEqual(error as? LocalSpeechError, .finalResultTimedOut) }
    }

    @MainActor func testCancellationCompletesWaiter() async {
        let result = LocalSpeechResult()
        let waiting = Task { try await result.wait() }
        await Task.yield()
        waiting.cancel()
        do { _ = try await waiting.value; XCTFail("expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testSingleSampleHasFiniteNoiseProfileAndCorrectPeak() {
        var detector = NoiseDetector(smoothing: 1)
        let p = detector.ingest([0.5])
        XCTAssertEqual(p.zeroCrossingRate, 0)
        XCTAssertEqual(p.peakDBFS, -6.0206, accuracy: 0.001)
        XCTAssertEqual(p.levelDBFS, p.peakDBFS, accuracy: 0.001)
    }
}
