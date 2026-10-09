import SwiftUI
import KotoroCore
import QuantTern

/// The root every app shell mounts: onboarding on a cold install, then the
/// working surface. Both `KotoroMac` and `KotoroIOS` render exactly this, so
/// the platforms cannot drift.
public struct KotoroRootView: View {
    @AppStorage(KotoroKeys.didOnboard) private var didOnboard = false

    public init() {}

    public var body: some View {
        if didOnboard {
            KotoroMainView()
        } else {
            OnboardingView { didOnboard = true }
        }
    }
}

/// The working surface: transcribe a take, read its QuantTern code, and reach
/// settings. Offline-first — it drives the on-device engine, never the network.
public struct KotoroMainView: View {
    public init() {}

    public var body: some View {
        TabView {
            TranscribeView()
                .tabItem { Label("Transcribe", systemImage: "waveform") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .frame(minWidth: 520, minHeight: 600)
    }
}

/// One take, end to end: gate the duration against the entitlement, run the
/// engine, tag the transcript, and show the emotional fingerprint.
///
/// Two modes:
/// - **Demo** — type a take, pick a duration, run the offline engine.
/// - **Live** — capture the headset mic and transcribe on-device as you go
///   (a walk in Tokyo, headphones in and out).
@MainActor
public struct TranscribeView: View {
    @AppStorage(KotoroKeys.engineID) private var engineID = "apple"
    @AppStorage(KotoroKeys.localeID) private var localeID = "en-US"
    @AppStorage(KotoroKeys.showEmotionCode) private var showEmotionCode = true
    @AppStorage(KotoroKeys.proUnlocked) private var proUnlocked = KotoroAppInfo.defaultPro

    @State private var take = "wow this is beautiful, thanks!"
    @State private var seconds = 60.0
    @State private var transcript: Transcript?
    @State private var errorText: String?

    @State private var liveEngine: LiveSpeechEngine?
    @State private var liveRunning = false
    @State private var liveBusy = false
    @State private var liveGeneration = 0
    @State private var liveText = ""
    @State private var liveSeconds = 0.0
    @State private var liveLevel: Float = -80
    @State private var liveNoise: NoiseClass = .silence

    public init() {}

    private var entitlement: Entitlement { proUnlocked ? .pro() : .free }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                TextEditor(text: $take)
                    .font(.body)
                    .frame(minHeight: 84)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))

                controls
                liveControls

                Button {
                    Task { await runTake() }
                } label: {
                    Label("Tag demo text", systemImage: "mic.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(liveRunning)

                result
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .onDisappear {
            liveGeneration += 1
            liveEngine?.cancel()
            liveEngine = nil
            liveRunning = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(KotoroAppInfo.name).font(.title2.bold())
            Text("On-device take · \(KotoroEngineChoice.named(engineID).name) · \(KotoroLocale.named(localeID).name)")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Duration")
                Spacer()
                Text(KotoroAppInfo.timecode(seconds))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(entitlement.allows(seconds: seconds) ? Color.secondary : Color.red)
            }
            Slider(value: $seconds, in: 0...KotoroAppInfo.maxTakeSeconds, step: 30)

            Picker("Language", selection: $localeID) {
                ForEach(KotoroLocale.all) { locale in
                    Text(locale.name).tag(locale.id)
                }
            }
            Text(KotoroLocale.named(localeID).detail)
                .font(.caption).foregroundStyle(.secondary)

            Toggle("Pro unlocked", isOn: $proUnlocked)
            Text(entitlement.isPro ? "Pro — unlimited takes + beta manuscripts."
                                   : "Free — up to 60 s per take.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var liveControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    Task { await toggleLive() }
                } label: {
                    Label(liveRunning ? "Stop" : "Live take",
                          systemImage: liveRunning ? "stop.circle.fill" : "record.circle")
                }
                .buttonStyle(.bordered)
                .tint(liveRunning ? .red : .accentColor)
                .disabled(liveBusy)

                if liveRunning || !liveText.isEmpty {
                    Text(KotoroAppInfo.timecode(liveSeconds))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if liveRunning {
                noiseBadge
            }
            Text("Headset mic in · same headset out. Recognition runs on-device; audio never leaves RAM.")
                .font(.caption).foregroundStyle(.secondary)
            if !liveText.isEmpty {
                Text(liveText)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
            }
        }
    }

    private var noiseBadge: some View {
        HStack(spacing: 8) {
            Circle().fill(noiseColor(liveNoise)).frame(width: 8, height: 8)
            Text(liveNoise.label).font(.system(.caption, design: .monospaced))
            Text(String(format: "%.0f dB", liveLevel))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func noiseColor(_ noise: NoiseClass) -> Color {
        switch noise {
        case .silence: return .secondary
        case .quiet:   return .green
        case .ambient: return .yellow
        case .noisy:   return .red
        }
    }

    @ViewBuilder private var result: some View {
        if let errorText {
            Label(errorText, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.callout)
        } else if let transcript {
            VStack(alignment: .leading, spacing: 8) {
                Text(transcript.text.isEmpty ? "(empty take)" : transcript.text)
                    .font(.body)
                if showEmotionCode {
                    let code = QuantTern.encode(transcript.vad ?? .neutral)
                    HStack(spacing: 12) {
                        Text(code.hex)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                        Text("magnitude \(code.magnitude)/3")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
        }
    }

    private func runTake() async {
        let engine = OfflineDemoEngine(text: take)
        let session = KotoroSession(entitlement: entitlement, engine: engine)
        do {
            transcript = try await session.transcribe(
                pcm: TakeAudio.take(seconds: seconds),
                sampleRate: TakeAudio.defaultSampleRate,
                seconds: seconds
            )
            errorText = nil
        } catch let error as KotoroError {
            transcript = nil
            switch error {
            case .freeLimitReached(let limit):
                errorText = String(format: "Free limit is %.0f s per take. Unlock Pro for unlimited.", limit)
            }
        } catch {
            transcript = nil
            errorText = "Take failed: \(error)"
        }
    }

    private func toggleLive() async {
        guard !liveBusy else { return }
        liveBusy = true
        let generation = liveGeneration
        defer { liveBusy = false }
        if liveRunning {
            let finished: Transcript?
            do { finished = try await liveEngine?.stop() }
            catch {
                errorText = error.localizedDescription
                liveRunning = false
                liveEngine = nil
                return
            }
            liveRunning = false
            liveEngine = nil
            if var t = finished {
                t.vad = EmotionTagger().vad(for: t.text)
                transcript = t
                errorText = nil
            }
            return
        }

        guard engineID == "apple" else {
            errorText = "This engine is not integrated yet. Select Apple on-device speech in Settings."
            return
        }
        guard LiveSpeechEngine.available(localeID: localeID) else {
            errorText = "On-device speech recognition is unavailable for \(KotoroLocale.named(localeID).name)."
            return
        }
        guard await LiveSpeechEngine.requestPermissions() else {
            errorText = LocalSpeechError.permissionDenied.localizedDescription
            return
        }

        guard generation == liveGeneration else { return }
        let engine = LiveSpeechEngine(localeID: localeID)
        engine.onFailure = { error in
            errorText = error.localizedDescription
            liveRunning = false
            liveEngine?.cancel()
            liveEngine = nil
        }
        engine.onUpdate = { update in
            Task { @MainActor in
                liveText = update.text
                liveSeconds = update.seconds
                liveLevel = update.levelDBFS
                liveNoise = update.noise
            }
        }
        do {
            try engine.start()
            liveEngine = engine
            liveRunning = true
            liveText = ""
            liveSeconds = 0
            transcript = nil
            errorText = nil
        } catch {
            errorText = "Live capture failed: \(error)"
        }
    }
}
