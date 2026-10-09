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

/// The signed-in surface: transcribe a take, read its QuantTern code, and reach
/// settings. Offline-first — it drives whatever on-device engine the shell has.
public struct KotoroMainView: View {
    public init() {}

    public var body: some View {
        TabView {
            TranscribeView()
                .tabItem { Label("Transcribe", systemImage: "waveform") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .frame(minWidth: 520, minHeight: 560)
    }
}

/// One take, end to end: gate the duration against the entitlement, run the
/// engine, tag the transcript, and show the emotional fingerprint.
public struct TranscribeView: View {
    @AppStorage(KotoroKeys.engineID) private var engineID = "apple"
    @AppStorage(KotoroKeys.showEmotionCode) private var showEmotionCode = true
    @AppStorage(KotoroKeys.minTakeSeconds) private var minTakeSeconds = 0.0
    @AppStorage(KotoroKeys.proUnlocked) private var proUnlocked = false

    @State private var take = "wow this is beautiful, thanks!"
    @State private var seconds = 30.0
    @State private var transcript: Transcript?
    @State private var errorText: String?

    public init() {}

    private var entitlement: Entitlement { proUnlocked ? .pro() : .free }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            TextEditor(text: $take)
                .font(.body)
                .frame(minHeight: 96)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))

            controls

            Button {
                Task { await runTake() }
            } label: {
                Label("Take", systemImage: "mic.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            result
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: 560, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(KotoroAppInfo.name).font(.title2.bold())
            Text("On-device take · \(KotoroEngineChoice.named(engineID).name)")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Duration")
                Spacer()
                Text(String(format: "%.0f s", seconds))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(entitlement.allows(seconds: seconds) ? Color.secondary : Color.red)
            }
            Slider(value: $seconds, in: 0...120, step: 5)

            Toggle("Pro unlocked", isOn: $proUnlocked)
            Text(entitlement.isPro ? "Pro — unlimited takes + beta manuscripts."
                                   : "Free — up to 60 s per take.")
                .font(.caption).foregroundStyle(.secondary)
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
}
