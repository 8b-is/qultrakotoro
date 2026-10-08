# Privacy — qUltraKotoro

## The short version

**Your data never leaves your device.** qUltraKotoro is offline-first and local by
construction — not by policy.

## What we collect

Nothing. There is no telemetry, no analytics, no account, no server in the core.

## What stays on your device

Your inputs and any local state live on your machine (and, if you enable it in
the app shell, your own iCloud/Keychain). The core never transmits them.

## Why this is trustworthy

It is a compile-time property: `scripts/check-offline.sh` fails the build if any
networking API appears in `Sources/`. See the CI badge.

## Contact

Open a discussion or a [security advisory](SECURITY.md).
