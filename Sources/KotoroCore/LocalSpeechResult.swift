import Foundation
import Speech

public enum LocalSpeechError: Error, LocalizedError, Equatable {
    case unavailable, onDeviceUnsupported, permissionDenied, finalResultTimedOut

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Speech recognition is unavailable for this language."
        case .onDeviceUnsupported: return "An on-device speech model is unavailable. Cloud fallback is disabled."
        case .permissionDenied: return "Microphone or speech recognition permission was denied."
        case .finalResultTimedOut: return "Speech recognition did not return a final result in time."
        }
    }
}

/// Both file and live recognition must pass this gate before submitting audio.
public enum LocalSpeechPolicy {
    public static func prepare(_ request: SFSpeechRecognitionRequest, available: Bool, supportsOnDevice: Bool) throws {
        try validate(available: available, supportsOnDevice: supportsOnDevice)
        request.requiresOnDeviceRecognition = true
    }
    public static func validate(available: Bool, supportsOnDevice: Bool) throws {
        guard supportsOnDevice else { throw LocalSpeechError.onDeviceUnsupported }
        guard available else { throw LocalSpeechError.unavailable }
    }
}

/// Retains the final result even when it arrives before Stop. Partials never
/// satisfy a waiter. Main-actor isolation serializes final/error/timeout races.
@MainActor
final class LocalSpeechResult {
    private var result: Result<String, Error>?
    private var waiters: [UUID: CheckedContinuation<String, Error>] = [:]

    func receive(text: String?, isFinal: Bool, error: Error?) {
        if isFinal, let text { finish(.success(text)) }
        else if let error { finish(.failure(error)) }
    }

    func finish(_ result: Result<String, Error>) {
        guard self.result == nil else { return }
        self.result = result
        let pending = Array(waiters.values)
        waiters.removeAll()
        for waiter in pending { waiter.resume(with: result) }
    }

    func wait(timeoutNanoseconds: UInt64 = 10_000_000_000) async throws -> String {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if let result { return try result.get() }
            let timer = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: timeoutNanoseconds) }
                catch { return }
                self?.finish(.failure(LocalSpeechError.finalResultTimedOut))
            }
            defer { timer.cancel() }
            return try await withCheckedThrowingContinuation { waiters[id] = $0 }
        } onCancel: {
            Task { @MainActor in
                self.waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
            }
        }
    }
}

@MainActor
public enum LocalFileSpeech {
    public static func transcribe(url: URL, localeID: String) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)) else {
            throw LocalSpeechError.unavailable
        }
        try LocalSpeechPolicy.validate(available: recognizer.isAvailable,
                                       supportsOnDevice: recognizer.supportsOnDeviceRecognition)
        guard await LiveSpeechEngine.requestSpeechPermission() else {
            throw LocalSpeechError.permissionDenied
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        try LocalSpeechPolicy.prepare(request, available: recognizer.isAvailable,
                                      supportsOnDevice: recognizer.supportsOnDeviceRecognition)
        request.shouldReportPartialResults = false
        let completion = LocalSpeechResult()
        let task = recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            Task { @MainActor in completion.receive(text: text, isFinal: final, error: error) }
        }
        defer { task.cancel() }
        return try await completion.wait(timeoutNanoseconds: 120_000_000_000)
    }
}
