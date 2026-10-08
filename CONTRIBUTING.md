# Contributing to qUltraKotoro

Thanks for helping. Small, tested, focused PRs land fastest.

## Setup

```bash
swift build
swift test
bash scripts/check-offline.sh     # the offline-first gate
```

## Rules

1. **Offline-first is non-negotiable.** No networking APIs in `Sources/`.
2. **Tests first.** Every behaviour change ships a test; `swift test` stays green.
3. **Semver.** Note user-visible changes in [CHANGELOG.md](CHANGELOG.md).
4. **Conventional commits** (`feat:`, `fix:`, `docs:`, `perf:`, `chore:`).
5. **Be kind.** See the [Code of Conduct](CODE_OF_CONDUCT.md).

## PR checklist

- [ ] `swift test` green
- [ ] `scripts/check-offline.sh` green
- [ ] CHANGELOG updated (if user-visible)
- [ ] docs updated
