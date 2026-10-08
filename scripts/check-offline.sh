#!/usr/bin/env bash
# Offline-first gate: the library must not reference networking APIs.
# Privacy is a compile-time property, not a setting.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -d "$root/Sources" ]; then echo "no Sources/ — skipping"; exit 0; fi
hits="$(grep -RInE 'URLSession|URLRequest|NWConnection|NWPathMonitor|import +Network|CFNetwork|\.dataTask\(' "$root/Sources" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*(///|//|\*)' || true)"
if [ -n "$hits" ]; then
  echo "offline-first: VIOLATION — networking API in Sources/:"; echo "$hits"; exit 1
fi
echo "offline-first: OK (no networking APIs in Sources/)"
