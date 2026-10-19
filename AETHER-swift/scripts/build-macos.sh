#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="AETHER"
VERSION="0.1.0"
CONFIGURATION="${CONFIGURATION:-release}"

swift build -c "$CONFIGURATION" --product AETHER
BIN="$(swift build -c "$CONFIGURATION" --product AETHER --show-bin-path)/AETHER"
BIN_DIR="$(dirname "$BIN")"

OUT="$ROOT/dist/macos/$APP_NAME.app"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

cp "$BIN" "$OUT/Contents/MacOS/AETHER"
chmod +x "$OUT/Contents/MacOS/AETHER"

FRAMEWORK="$BIN_DIR/PackageFrameworks/WebRTC.framework"
if [[ ! -d "$FRAMEWORK" ]]; then
    echo "Missing WebRTC.framework at $FRAMEWORK" >&2
    exit 1
fi
mkdir -p "$OUT/Contents/Frameworks"
cp -R "$FRAMEWORK" "$OUT/Contents/Frameworks/"
install_name_tool -add_rpath @executable_path/../Frameworks "$OUT/Contents/MacOS/AETHER"

sed "s/__VERSION__/$VERSION/g" "$ROOT/Packaging/Info.plist" \
    > "$OUT/Contents/Info.plist"

ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
if swift "$ROOT/scripts/make-icon.swift" "$ICONSET" >/dev/null 2>&1 \
    && command -v iconutil >/dev/null 2>&1; then
    if iconutil -c icns "$ICONSET" -o "$OUT/Contents/Resources/AppIcon.icns"; then
        echo "Generated AppIcon.icns"
    fi
fi
rm -rf "$ICONSET"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$OUT" >/dev/null 2>&1 || true
fi

echo
echo "Built: $OUT"
echo "Run:   open \"$OUT\""
