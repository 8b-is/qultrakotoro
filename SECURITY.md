# Security Policy — qUltraKotoro

## Supported versions

| version | supported |
|---|---|
| 0.1.0.x | ✅ |

## Reporting a vulnerability

Please **do not** open a public issue. Use GitHub's
[private vulnerability reporting](https://github.com/8b-is/qultrakotoro/security/advisories/new)
or email the maintainers. We aim to acknowledge within 72 hours.

Include: a description, repro steps, the affected version, and any proof-of-concept.

## Scope

qUltraKotoro is **offline-first**: the core makes no network calls by design
(enforced in CI). The most valuable reports are ones that show it *can* reach the
network, leak local data, or break the offline guarantee.
