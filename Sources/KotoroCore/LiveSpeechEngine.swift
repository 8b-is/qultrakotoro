import Foundation
import AVFoundation
import Speech

/// Live on-device capture + transcription for field takes — e.g. a walk with the
/// headset mic as input and the same headset as output. Nothing leaves the
/// device: recognition is forced on-device (`requiresOnDeviceRecognition`) and
/// the audio only ever lives in RAM.
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

    /// Live partials. Delivered on an audio/recognition thread — hop to the
    /// main actor before touching UI.
    public var onUpdate: (@Sendable (Update) -> Void)?
    public private(set) var isRunning = false

    public init(localeID: String = "en-US") {
        self.localeID = localeID
        super.init()
    }

    public static func available(localeID: String = "en-US") -> Bool {
        SFSpeechRecognizer(locale: Locale(identifier: localeID))?.isAvailable ?? false
    }

    /// Ask for speech + microphone access. Returns true only if both are granted.
    @discardableResult
    public static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let mic = await requestMicrophone()
        return speech && mic
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
        try configureAudioSession()
        latest = ""
        detector.reset()
        startedAt = Date()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer?.supportsOnDeviceRecognition ?? false
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            self?.detector.ingest(Self.samples(from: buffer))
            self?.emit(isFinal: false)
        }

        engine.prepare()
        try engine.start()

        task = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            self.latest = result.bestTranscription.formattedString
            self.emit(isFinal: result.isFinal)
        }
        isRunning = true
    }

    /// Stops capture and returns the take: the transcript so far plus the wall
    /// clock duration actually recorded.
    public func stop() async -> Transcript {
        guard isRunning else { return Transcript(text: latest, seconds: 0) }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.finish()
        isRunning = false

        let seconds = Date().timeIntervalSince(startedAt ?? Date())
        let transcript = Transcript(text: latest, seconds: seconds)
        task = nil
        request = nil
        deactivateAudioSession()
        return transcript
    }

    private func emit(isFinal: Bool) {
        let seconds = Date().timeIntervalSince(startedAt ?? Date())
        let profile = detector.profile
        onUpdate?(Update(text: latest, seconds: seconds, isFinal: isFinal,
                         levelDBFS: profile.levelDBFS, noise: profile.classification))
    }

    private static func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
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
