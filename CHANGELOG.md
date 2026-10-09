# Changelog

All notable changes to qUltraKotoro are documented here.
This project adheres to [Semantic Versioning](https://semver.org).

## [0.4.0] — 2026-10-09

### Added
- **Multilingual takes** — a `KotoroLocale` picker (English, 日本語, 中文简体,
  中文繁體 · Taiwan, 臺語) drives `LiveSpeechEngine(localeID:)`, with the chosen
  language shown on the surface and in Settings. Unknown tags fall back safely.
- `scripts/fetch-model.sh` now defaults to the **multilingual** model and warns
  if you pick an English-only `*.en` build.

### Changed
- `KotoroAppInfo.version` → `0.4.0`.

## [0.3.0] — 2026-10-09

### Added
- **Live take** — `LiveSpeechEngine` captures the headset mic and transcribes
  on-device (`SFSpeechRecognizer`, `requiresOnDeviceRecognition`), streaming
  partials into `TranscribeView`. Headset in, same headset out; iOS routes with
  a `.playAndRecord` session. Nothing leaves the device.
- **Long takes** — the duration ceiling is now `KotoroAppInfo.maxTakeSeconds`
  (30 min, with headroom) with an `mm:ss` / `h:mm:ss` timecode.
- Microphone + speech-recognition usage strings in the generated `Info.plist`.
- **`scripts/fetch-model.sh`** — one-time fetch of the best local whisper model
  (`ggml-large-v3-turbo`) into `./models/`, so the app stays offline at runtime.

### Changed
- **Pro is the default** for this build (`KotoroAppInfo.defaultPro`), so takes
  are unlimited and beta manuscripts are unlocked out of the box.
- `SettingsView` reads the Pro flag from `AppStorage` and exposes a toggle.
- `KotoroAppInfo.version` → `0.3.0`.

## [0.2.0] — 2026-10-09

### Added
- **`KotoroMac` app shell** — a runnable macOS SwiftUI app
  (`swift run KotoroMac`) mounting the shared surface.
- **`KotoroIOS` app shell** — the iOS SwiftUI entry point over the same surface.
- **`KotoroUI` working surface** — `KotoroRootView` / `KotoroMainView` /
  `TranscribeView`: the onboarding gate plus a take that runs the session path
  (entitlement gate → engine → QuantTern emotion code) and a Pro toggle.
- **`KotoroCore` offline demo engine** — `TakeAudio` + `OfflineDemoEngine`,
  a dependency-free `SpeechToText` so the whole path runs with no network.
- `TakeFlowTests` pinning the engine duration, the emotion tag, and the free gate.
- **`scripts/build-mac-app.sh`** — assembles `build/qUltraKotoro.app` (Info.plist,
  `.icns` from the appiconset, ad-hoc signature) with no Xcode project, so the
  macOS app builds and launches end to end.

### Changed
- `KotoroAppInfo.version` → `0.2.0`.

## [0.1.1] — 2026-10-09

### Added
- `KotoroUI` SwiftUI target: `OnboardingView` (first-install flow mirroring
  https://setup.vaked.dev) and `SettingsView` (engine, emotion, access,
  privacy, sync, about).
- App icon asset catalog (`AppIcon.appiconset`) for iOS + macOS.
- Setup-guide links in the README.

## [0.1.0] — 2026-10-09

### Added
- Initial release of qUltraKotoro.
- Offline-first core (no networking APIs; enforced in CI).
- Tests (`swift test`) and the offline-first gate (`scripts/check-offline.sh`).
- Repository furniture: README, SECURITY, PRIVACY, TERMS, CONTRIBUTING,
  CODE_OF_CONDUCT, issue/PR templates, CI.
