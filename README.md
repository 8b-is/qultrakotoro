<div align="center">

# qUltraKotoro

**superwhisper on steroids — on-device STT + an emotional QuantTern code**

[![swift](https://img.shields.io/badge/Swift-5.9%2B-FA7343?logo=swift&logoColor=white)](https://swift.org)
[![platforms](https://img.shields.io/badge/platforms-iOS%2017%20·%20macOS%2014-000000?logo=apple&logoColor=white)](#install)
[![offline-first](https://img.shields.io/badge/offline--first-%E2%9C%93-9dff5c)](#offline-first)
[![CI](https://github.com/8b-is/qultrakotoro/actions/workflows/ci.yml/badge.svg)](https://github.com/8b-is/qultrakotoro/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-b8is?style=flat)](CONTRIBUTING.md)
[![semver](https://img.shields.io/badge/version-0.6.0-9dff5c)](CHANGELOG.md)

</div>

---

## Table of contents

- [What it is](#what-it-is)
- [Features](#features)
- [Install](#install)
- [Setup guide](#setup-guide)
- [Usage](#usage)
- [Architecture](#architecture)
- [Offline-first](#offline-first)
- [Security](#security) · [Privacy](#privacy)
- [Versioning](#versioning)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license) · [Citation](#citation)

## What it is

qUltraKotoro — superwhisper on steroids — on-device STT + an emotional QuantTern code. Part of the **8b-is** constellation; built to run fully on device.

## Features

| | |
|---|---|
| 🧠 | See the module docs in `Sources/` and the landing site. |
| 🔒 | **Offline-first.** No networking APIs anywhere in the core; enforced in CI. |
| 📱 | iOS 17+ and macOS 14+. |
| ✅ | Tests pin behaviour; `swift test` is the contract. |

## Install

```bash
git clone https://github.com/8b-is/qultrakotoro.git
cd qultrakotoro
swift build
swift test
swift run KotoroMac              # run the macOS app directly
scripts/build-mac-app.sh        # ...or a real .app bundle
open build/qUltraKotoro.app
swift run kotorocli help        # the command-line tool
```

Add as a dependency:

```swift
.package(url: "https://github.com/8b-is/qultrakotoro.git", from: "0.1.0")
```

## Setup guide

Meet **Onboarding** on first launch: it walks you from a cold install to a
working, fully on-device session in a few taps.

- **Guided setup:** <https://setup.vaked.dev> — the ELI5, illustrated walkthrough
  (macOS + iPhone tabs) covering Osaurus, Apple Intelligence, HuggingFace models,
  Shortcuts, permissions, and offline mode.
- **In-app onboarding:** the `KotoroUI` target ships `OnboardingView` for the
  first-install flow and `SettingsView` for everything after that.
- **The offline gate:** `scripts/check-offline.sh` fails CI if the core ever
  reaches for the network. Privacy is a compile-time property here.

## Usage

```swift
import KotoroCore
// see Sources/KotoroCore for the public surface
```

**Live takes.** In the app, hit *Live take* to capture the headset mic and
transcribe on-device as you go — headset in, same headset out. Tap *Stop* to
keep the transcript and its QuantTern code. Pro (the default in this build)
removes the 60 s ceiling; takes run up to `KotoroAppInfo.maxTakeSeconds`. A
**noise badge** shows the room's level (silence / quiet / ambient / noisy, in
dB) so you can tell whether a take came out clean.

## Models

The default engine is Apple's built-in on-device recogniser — **no download**.
For maximum quality with the whisper.cpp engine, fetch the best **multilingual**
model once (this is the only step that ever touches the network, and you run it
yourself). One download covers English, Japanese, Chinese (Simplified and
Traditional/Taiwan) and best-effort Taiwanese Hokkien:

```bash
scripts/fetch-model.sh          # ggml-large-v3-turbo, into ./models/
```

The app keeps its offline-first promise: recognition is on-device, and no audio
or text ever leaves the machine.

## Command line

`kotorocli` is the same brain without the window — off-device audio files, emotion
tagging at the prompt, and a live mic take. It is offline-first too.

```bash
swift run kotorocli emotion "i love this warm beautiful hope" --json
swift run kotorocli noise recording.wav            # level, peak, zcr, class
swift run kotorocli transcribe recording.wav --locale ja-JP
swift run kotorocli live 30 --locale zh-TW         # 30 s headset take
```

| Command | What it does |
|---------|--------------|
| `emotion <text>` | VAD + QuantTern code (`--json` for machines) |
| `noise <audio>` | noise profile: level, peak, zero-crossing rate, class |
| `transcribe <audio>` | on-device file transcription + emotion code |
| `live [seconds]` | mic take, streaming text and a live noise badge |
| `engines` · `locales` | list the STT engines and language tags |

## Architecture

```
qultrakotoro/
├── Package.swift
├── Sources/KotoroCore/          # the library (offline-first core)
├── Sources/KotoroUI/            # SwiftUI: Onboarding, Transcribe, Settings
├── Sources/KotoroMac/           # macOS app shell (swift run KotoroMac)
├── Sources/KotoroIOS/           # iOS app shell (Xcode / SwiftPM iOS build)
├── Sources/KotoroCLI/           # command-line tool (swift run kotorocli)
├── Tests/                  # swift test
├── scripts/check-offline.sh# the offline-first gate (runs in CI)
└── .github/                # templates, CODEOWNERS, CI
```

## Offline-first

qUltraKotoro must work with the network off. The gate `scripts/check-offline.sh` scans
`Sources/` for networking APIs (`URLSession`, `URLRequest`, `NWConnection`,
`import Network`) and **fails the build** if any appear. Privacy is not a setting;
it is a compile-time property. See [PRIVACY.md](PRIVACY.md).

## Security

See [SECURITY.md](SECURITY.md) for how to report a vulnerability. Do not open a
public issue for security problems.

## Privacy

See [PRIVACY.md](PRIVACY.md). In one line: **your data never leaves the device.**

## Versioning

[Semantic Versioning](https://semver.org). The current version is **0.6.0** — see
[CHANGELOG.md](CHANGELOG.md). Releases are tagged `v0.6.0`.

## Roadmap

See the issues and the [CHANGELOG](CHANGELOG.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md). Small, tested PRs are the fastest path.

## License

[Apache-2.0](LICENSE) © the 8b-is constellation.

## Citation

```bibtex
@software{qultrakotoro,
  title  = {qUltraKotoro},
  author = {8b-is},
  year   = {2026},
  url    = {https://github.com/8b-is/qultrakotoro}
}
```
