import Foundation

/// Shared, UI-facing facts about the app. Kept free of any framework so the
/// values are testable and identical across iOS and macOS.
public enum KotoroAppInfo {
    public static let name = "qUltraKotoro"
    public static let version = "0.4.0"

    /// Personal build default: start in Pro (unlimited takes + beta manuscripts).
    public static let defaultPro = true

    /// Longest take the UI exposes. Pro is unlimited by design; this is just the
    /// slider ceiling (a 30-minute walk, with headroom).
    public static let maxTakeSeconds: Double = 1800

    public static let landingURL = "https://kotoro.vaked.dev"
    public static let setupGuideURL = "https://setup.vaked.dev"
    public static let sourceURL = "https://github.com/8b-is/qultrakotoro"

    public static var landing: URL { URL(string: landingURL)! }
    public static var setupGuide: URL { URL(string: setupGuideURL)! }
    public static var source: URL { URL(string: sourceURL)! }

    /// `mm:ss` (or `h:mm:ss` past an hour) for a take duration.
    public static func timecode(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

/// UserDefaults keys shared between onboarding and settings so a choice made
/// in one screen is visible in the other.
public enum KotoroKeys {
    public static let didOnboard = "kotoro.didOnboard"
    public static let engineID = "kotoro.engineID"
    public static let localeID = "kotoro.localeID"
    public static let showEmotionCode = "kotoro.showEmotionCode"
    public static let minTakeSeconds = "kotoro.minTakeSeconds"
    public static let offlineOnly = "kotoro.offlineOnly"
    public static let osaurusEndpoint = "kotoro.osaurusEndpoint"
    public static let iCloudSync = "kotoro.iCloudSync"
    public static let betaManuscripts = "kotoro.betaManuscripts"
    public static let proUnlocked = "kotoro.proUnlocked"
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
              detail: "Run scripts/fetch-model.sh for the best local model; fully offline.", symbol: "cpu"),
        .init(id: "parakeet", name: "Parakeet (local)",
              detail: "Fast multilingual on-device transcription.", symbol: "bird"),
        .init(id: "osaurus", name: "Osaurus (macOS, localhost)",
              detail: "Local model server on port 1337.", symbol: "desktopcomputer"),
    ]

    public static func named(_ id: String) -> KotoroEngineChoice {
        all.first { $0.id == id } ?? all[0]
    }
}

/// The spoken languages the recognizer can target. All are offline; the
/// multilingual model covers them without swapping downloads.
public struct KotoroLocale: Identifiable, Hashable, Sendable {
    public let id: String        // BCP-47 language tag
    public let name: String
    public let detail: String

    public init(id: String, name: String, detail: String) {
        self.id = id; self.name = name; self.detail = detail
    }

    public static let all: [KotoroLocale] = [
        .init(id: "en-US", name: "English", detail: "English (United States)"),
        .init(id: "ja-JP", name: "日本語", detail: "Japanese"),
        .init(id: "zh-CN", name: "中文（简体）", detail: "Chinese (Simplified)"),
        .init(id: "zh-TW", name: "中文（繁體）", detail: "Chinese (Traditional · Taiwan)"),
        .init(id: "nan-TW", name: "臺語", detail: "Taiwanese Hokkien (best-effort)"),
    ]

    public static func named(_ id: String) -> KotoroLocale {
        all.first { $0.id == id } ?? all[0]
    }
}
