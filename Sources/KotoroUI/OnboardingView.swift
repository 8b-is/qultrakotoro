import SwiftUI
import KotoroCore

/// First-install onboarding. A short, honest, on-device setup: pick a local
/// engine, learn the Shortcut, and confirm that nothing ever leaves the device.
/// Mirrors the guided walkthrough at https://setup.vaked.dev.
public struct OnboardingView: View {
    @State private var step = 0
    @AppStorage(KotoroKeys.engineID) private var engineID = "apple"
    private let onFinish: () -> Void

    public init(onFinish: @escaping () -> Void = {}) {
        self.onFinish = onFinish
    }

    private var pages: [OnboardingPage] { OnboardingPage.all(engineID: engineID) }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: pages[step].symbol)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.tint)
                        .padding(.top, 8)

                    Text(pages[step].title)
                        .font(.largeTitle.bold())

                    Text(pages[step].body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if pages[step].enginePicker {
                        enginePicker
                    }

                    if let bullets = pages[step].bullets {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(bullets, id: \.self) { line in
                                Label(line, systemImage: "checkmark.circle")
                                    .font(.callout)
                            }
                        }
                    }

                    if let link = pages[step].guide {
                        Link(destination: link) {
                            Label("Open the illustrated setup guide", systemImage: "book")
                        }
                        .font(.callout)
                    }
                }
                .frame(maxWidth: 480, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity)
            }

            Divider()

            HStack(spacing: 12) {
                Button("Skip") { finish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }

                Spacer()

                if step > 0 {
                    Button("Back") { step -= 1 }
                }

                Button(step == pages.count - 1 ? "Start" : "Continue") {
                    if step == pages.count - 1 { finish() } else { step += 1 }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    private var enginePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(KotoroEngineChoice.all) { choice in
                Button {
                    engineID = choice.id
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: choice.symbol).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(choice.name).font(.headline)
                            Text(choice.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if engineID == choice.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(engineID == choice.id ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func finish() {
        onFinish()
    }
}

/// The content of a single onboarding page. Data lives in `OnboardingPage.all`
/// so the same flow is reused by both platforms and can be unit-tested.
public struct OnboardingPage: Hashable {
    public let title: String
    public let body: String
    public let symbol: String
    public let enginePicker: Bool
    public let bullets: [String]?
    public let guide: URL?

    public static func all(engineID: String) -> [OnboardingPage] {
        [
            .init(title: "Welcome to \(KotoroAppInfo.name)",
                  body: "On-device speech-to-text with an emotional QuantTern fingerprint. Recognition requires a local Apple speech model on your \(platformName). No account is required and cloud recognition fallback is disabled.",
                  symbol: "hand.wave", enginePicker: false, bullets: nil, guide: nil),

            .init(title: engineTitle,
                  body: engineBody,
                  symbol: platformSymbol, enginePicker: true, bullets: nil, guide: nil),

            .init(title: "Add an on-device model",
                  body: "This version uses Apple Speech. An on-device model must be available for your selected language; otherwise transcription stops with an error. Whisper, Parakeet, and Osaurus are not integrated yet.",
                  symbol: "arrow.down.circle", enginePicker: false,
                  bullets: ["Models stay on-device", "Works with airplane mode on", "No sign-in required"], guide: nil),

            .init(title: "Make the Shortcut",
                  body: "Add the qUltraKotoro Shortcut so you can transcribe from the Share Sheet, a file, or a dictation trigger — without opening the app.",
                  symbol: "command", enginePicker: false,
                  bullets: ["Share Sheet → Transcribe", "File → Transcribe", "Dictation → Transcribe"], guide: KotoroAppInfo.setupGuide),

            .init(title: "Stay offline, on purpose",
                  body: "Audio recognition requests require an on-device model. A source lint check also flags common networking APIs, but is not a substitute for offline device testing.",
                  symbol: "lock.shield", enginePicker: false,
                  bullets: ["Offline-first gate enforced in CI", "Free for takes up to 60 seconds", "Pro (€4.20/mo) unlocks unlimited + the beta manuscripts"], guide: nil),

            .init(title: "You're set",
                  body: "Pick a take and speak. Free covers one minute per take; Pro removes the limit and opens the beta/WIP anime manuscripts.",
                  symbol: "sparkles", enginePicker: false,
                  bullets: nil, guide: nil),
        ]
    }

    private static var platformName: String {
        #if os(macOS)
        "Mac"
        #else
        "iPhone"
        #endif
    }

    private static var platformSymbol: String {
        #if os(macOS)
        "desktopcomputer"
        #else
        "iphone"
        #endif
    }

    private static var engineTitle: String {
        #if os(macOS)
        "Point it at your Mac"
        #else
        "Choose on-device speech"
        #endif
    }

    private static var engineBody: String {
        #if os(macOS)
        "Use Apple Speech with a supported local language model. Other engine adapters are planned, not enabled."
        #else
        "Select a language supported by Apple on-device speech on this iPhone. If the local model is unavailable, recognition will not fall back to a server."
        #endif
    }
}
