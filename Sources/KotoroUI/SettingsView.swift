import SwiftUI
import KotoroCore
import QuantTern

/// The epic settings surface: engine, emotion, access, privacy, sync, about.
public struct SettingsView: View {
    @AppStorage(KotoroKeys.engineID) private var engineID = "apple"
    @AppStorage(KotoroKeys.showEmotionCode) private var showEmotionCode = true
    @AppStorage(KotoroKeys.minTakeSeconds) private var minTakeSeconds = 0.0
    @AppStorage(KotoroKeys.offlineOnly) private var offlineOnly = true
    @AppStorage(KotoroKeys.osaurusEndpoint) private var osaurusEndpoint = "http://127.0.0.1:1337"
    @AppStorage(KotoroKeys.iCloudSync) private var iCloudSync = false
    @AppStorage(KotoroKeys.betaManuscripts) private var betaManuscripts = false

    private let entitlement: Entitlement
    private let sample: String

    public init(entitlement: Entitlement = .free,
                sample: String = "wow this is beautiful, thanks!") {
        self.entitlement = entitlement
        self.sample = sample
    }

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
                Toggle("Beta / WIP anime manuscripts", isOn: $betaManuscripts)
                    .disabled(!entitlement.isPro)
            }

            Section("Privacy") {
                Toggle("Offline only", isOn: $offlineOnly)
                Text("qUltraKotoro never calls the network. The build fails in CI if a networking API ever appears in the core.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Sync") {
                Toggle("Sync transcripts with iCloud", isOn: $iCloudSync)
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
