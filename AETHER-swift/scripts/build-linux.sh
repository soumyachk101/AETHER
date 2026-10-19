#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${CONFIGURATION:-release}"
swift build -c "$CONFIGURATION" --product AETHER
BIN="$(swift build -c "$CONFIGURATION" --product AETHER --show-bin-path)/AETHER"

OUT="$ROOT/dist/linux/AETHER"
mkdir -p "$(dirname "$OUT")"
install -m 755 "$BIN" "$OUT"
echo "Built: $OUT"
