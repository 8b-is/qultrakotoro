<div align="center">

# qUltraKotoro

**superwhisper on steroids — on-device STT + an emotional QuantTern code**

[![swift](https://img.shields.io/badge/Swift-5.9%2B-FA7343?logo=swift&logoColor=white)](https://swift.org)
[![platforms](https://img.shields.io/badge/platforms-iOS%2017%20·%20macOS%2014-000000?logo=apple&logoColor=white)](#install)
[![offline-first](https://img.shields.io/badge/offline--first-%E2%9C%93-9dff5c)](#offline-first)
[![CI](https://github.com/8b-is/qultrakotoro/actions/workflows/ci.yml/badge.svg)](https://github.com/8b-is/qultrakotoro/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-b8is?style=flat)](CONTRIBUTING.md)
[![semver](https://img.shields.io/badge/version-0.1.1-9dff5c)](CHANGELOG.md)

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

## Architecture

```
qultrakotoro/
├── Package.swift
├── Sources/KotoroCore/          # the library (offline-first core)
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

[Semantic Versioning](https://semver.org). The current version is **0.1.0** — see
[CHANGELOG.md](CHANGELOG.md). Releases are tagged `v0.1.0`.

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
