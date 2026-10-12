import SwiftUI
import KotoroCore
import QuantTern

/// The epic settings surface: engine, emotion, access, privacy, sync, about.
public struct SettingsView: View {
    @AppStorage(KotoroKeys.engineID) private var engineID = "apple"
    @AppStorage(KotoroKeys.localeID) private var localeID = "en-US"
    @AppStorage(KotoroKeys.showEmotionCode) private var showEmotionCode = true
    @AppStorage(KotoroKeys.minTakeSeconds) private var minTakeSeconds = 0.0
    @AppStorage(KotoroKeys.offlineOnly) private var offlineOnly = true
    @AppStorage(KotoroKeys.osaurusEndpoint) private var osaurusEndpoint = "http://127.0.0.1:1337"
    @AppStorage(KotoroKeys.iCloudSync) private var iCloudSync = false
    @AppStorage(KotoroKeys.betaManuscripts) private var betaManuscripts = false

    private let sample: String

    @AppStorage(KotoroKeys.proUnlocked) private var proUnlocked = KotoroAppInfo.defaultPro

    public init(sample: String = "wow this is beautiful, thanks!") {
        self.sample = sample
    }

    private var entitlement: Entitlement { proUnlocked ? .pro() : .free }

    public var body: some View {
        Form {
            Section("Engine") {
                Picker("On-device engine", selection: $engineID) {
                    ForEach(KotoroEngineChoice.all) { choice in
                        Label(choice.name, systemImage: choice.symbol).tag(choice.id)
                    }
                }
                Text(KotoroEngineChoice.named(engineID).detail)
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Language", selection: $localeID) {
                    ForEach(KotoroLocale.all) { locale in
                        Text(locale.name).tag(locale.id)
                    }
                }
                Text(KotoroLocale.named(localeID).detail)
                    .font(.caption).foregroundStyle(.secondary)
                if engineID == "osaurus" {
                    TextField("Osaurus endpoint", text: $osaurusEndpoint)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section("Emotion") {
                Toggle("Show the QuantTern emotion code", isOn: $showEmotionCode)
                if showEmotionCode {
                    let code = EmotionTagger().code(for: sample)
                    HStack {
                        Text("Preview").foregroundStyle(.secondary)
                        Spacer()
                        Text(code.hex)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                HStack {
                    Text("Minimum take")
                    Spacer()
                    Stepper(value: $minTakeSeconds, in: 0...10, step: 0.5) {
                        Text(String(format: "%.1f s", minTakeSeconds))
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

            Section("Access") {
                HStack {
                    Label(entitlement.isPro ? "Pro" : "Free",
                          systemImage: entitlement.isPro ? "star.circle.fill" : "circle")
                    Spacer()
                    Text(entitlement.isPro ? "unlimited" : "≤ 60 s / take")
                        .foregroundStyle(.secondary)
                }
                if !entitlement.isPro {
                    Link("Upgrade — €4.20 / month", destination: KotoroAppInfo.landing)
                }
                Toggle("Pro unlocked", isOn: $proUnlocked)
                Toggle("Beta / WIP anime manuscripts", isOn: $betaManuscripts)
                    .disabled(!entitlement.isPro)
            }

            Section("Privacy") {
                Toggle("Offline only", isOn: .constant(true)).disabled(true)
                Text("Speech recognition requires an available on-device model. Cloud fallback is disabled. Opening external links uses your browser.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Sync") {
                Text("Transcript sync is not implemented.")
            }

            Section("About") {
                LabeledContent("Version", value: KotoroAppInfo.version)
                Link("Setup guide", destination: KotoroAppInfo.setupGuide)
                Link("Landing", destination: KotoroAppInfo.landing)
                Link("Source", destination: KotoroAppInfo.source)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 560)
    }
}
