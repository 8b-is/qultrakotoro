# Changelog

All notable changes to qUltraKotoro are documented here.
This project adheres to [Semantic Versioning](https://semver.org).

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
