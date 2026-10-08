import Foundation

/// Shared, UI-facing facts about the app. Kept free of any framework so the
/// values are testable and identical across iOS and macOS.
public enum KotoroAppInfo {
    public static let name = "qUltraKotoro"
    public static let version = "0.1.1"

    public static let landingURL = "https://kotoro.vaked.dev"
    public static let setupGuideURL = "https://setup.vaked.dev"
    public static let sourceURL = "https://github.com/8b-is/qultrakotoro"

    public static var landing: URL { URL(string: landingURL)! }
    public static var setupGuide: URL { URL(string: setupGuideURL)! }
    public static var source: URL { URL(string: sourceURL)! }
}

/// UserDefaults keys shared between onboarding and settings so a choice made
/// in one screen is visible in the other.
public enum KotoroKeys {
    public static let didOnboard = "kotoro.didOnboard"
    public static let engineID = "kotoro.engineID"
    public static let showEmotionCode = "kotoro.showEmotionCode"
    public static let minTakeSeconds = "kotoro.minTakeSeconds"
    public static let offlineOnly = "kotoro.offlineOnly"
    public static let osaurusEndpoint = "kotoro.osaurusEndpoint"
    public static let iCloudSync = "kotoro.iCloudSync"
    public static let betaManuscripts = "kotoro.betaManuscripts"
}

/// The local STT engines the app can point at. All on device.
public struct KotoroEngineChoice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let detail: String
    public let symbol: String

    public init(id: String, name: String, detail: String, symbol: String) {
        self.id = id; self.name = name; self.detail = detail; self.symbol = symbol
    }

    public static let all: [KotoroEngineChoice] = [
        .init(id: "apple", name: "Apple on-device speech",
              detail: "Free, built in, zero setup. Great default.", symbol: "waveform"),
        .init(id: "whisper.cpp", name: "whisper.cpp (local)",
              detail: "Bring a GGML model; fully offline.", symbol: "cpu"),
        .init(id: "parakeet", name: "Parakeet (local)",
              detail: "Fast multilingual on-device transcription.", symbol: "bird"),
        .init(id: "osaurus", name: "Osaurus (macOS, localhost)",
              detail: "Local model server on port 1337.", symbol: "desktopcomputer"),
    ]

    public static func named(_ id: String) -> KotoroEngineChoice {
        all.first { $0.id == id } ?? all[0]
    }
}
