import Foundation
import AVFoundation
import Speech

/// Live on-device capture + transcription for field takes — e.g. a walk with the
/// headset mic as input and the same headset as output. Nothing leaves the
/// device: recognition is forced on-device (`requiresOnDeviceRecognition`) and
/// the audio only ever lives in RAM.
@MainActor
public final class LiveSpeechEngine: NSObject {
    public struct Update: Sendable {
        public let text: String
        public let seconds: Double
        public let isFinal: Bool
        public let levelDBFS: Float
        public let noise: NoiseClass
    }

    private let engine = AVAudioEngine()
    private let localeID: String
    private lazy var recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var startedAt: Date?
    private var latest = ""
    private var detector = NoiseDetector()
    private var completion = LocalSpeechResult()
    private var takeID = UUID()
    private var tapInstalled = false
    private var duration: Double = 0
    public var onFailure: ((Error) -> Void)?

    /// Live partials delivered on the main actor.
    public var onUpdate: (@Sendable (Update) -> Void)?
    public private(set) var isRunning = false

    public init(localeID: String = "en-US") {
        self.localeID = localeID
        super.init()
    }

    public static func available(localeID: String = "en-US") -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)) else { return false }
        return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
    }

    /// Ask for speech + microphone access. Returns true only if both are granted.
    @discardableResult
    public static func requestPermissions() async -> Bool {
        let speech = await requestSpeechPermission()
        guard speech else { return false }
        return await requestMicrophone()
    }

    public static func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    private static func requestMicrophone() async -> Bool {
        #if os(iOS)
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        #else
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
        #endif
    }

    public func start() throws {
        guard !isRunning else { return }
        guard let recognizer else { throw LocalSpeechError.unavailable }
        try LocalSpeechPolicy.validate(available: recognizer.isAvailable,
                                       supportsOnDevice: recognizer.supportsOnDeviceRecognition)
        latest = ""
        detector.reset()
        startedAt = Date()
        duration = 0
        completion = LocalSpeechResult()
        takeID = UUID()
        let id = takeID

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        try LocalSpeechPolicy.prepare(request, available: recognizer.isAvailable,
                                      supportsOnDevice: recognizer.supportsOnDeviceRecognition)
        self.request = request
        try configureAudioSession()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            deactivateAudioSession()
            self.request = nil
            throw LocalSpeechError.unavailable
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let samples = Self.samples(from: buffer)
            Task { @MainActor in
                guard let self, self.takeID == id, self.isRunning else { return }
                self.detector.ingest(samples)
                self.emit(isFinal: false)
            }
        }

        tapInstalled = true
        do {
            engine.prepare()
            try engine.start()
        } catch {
            stopCapture()
            request.endAudio()
            self.request = nil
            throw error
        }
        isRunning = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            Task { @MainActor in
                guard let self, self.takeID == id else { return }
                if let text { self.latest = text }
                self.completion.receive(text: text, isFinal: final, error: error)
                self.emit(isFinal: final)
                if final || error != nil {
                    self.stopCapture()
                    self.request?.endAudio()
                    if !final, let error { self.onFailure?(error) }
                }
            }
        }
    }

    /// End input, then await the final transcript (or an explicit failure).
    public func stop() async throws -> Transcript {
        stopCapture()
        request?.endAudio()
        defer {
            task?.cancel()
            task = nil
            request = nil
        }
        let text = try await completion.wait()
        return Transcript(text: text, seconds: duration)
    }

    public func cancel() {
        stopCapture()
        takeID = UUID()
        completion.finish(.failure(CancellationError()))
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    private func stopCapture() {
        if isRunning { duration = Date().timeIntervalSince(startedAt ?? Date()) }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        isRunning = false
        deactivateAudioSession()
    }

    private func emit(isFinal: Bool) {
        let seconds = Date().timeIntervalSince(startedAt ?? Date())
        let profile = detector.profile
        onUpdate?(Update(text: latest, seconds: seconds, isFinal: isFinal,
                         levelDBFS: profile.levelDBFS, noise: profile.classification))
    }

    nonisolated private static func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    private func configureAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.allowBluetooth, .defaultToSpeaker])
        try session.setActive(true)
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
