#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist/linux"
RELEASE_DIR="$PROJECT_DIR/dist/release"
WEB_DIR="$(cd "$PROJECT_DIR/../AETHER-web" && pwd)"
VERSION="$(sed -n 's/^version = "\([^"]*\)"/\1/p' "$PROJECT_DIR/Cargo.toml" | head -n 1)"

cd "$PROJECT_DIR"

command -v cargo >/dev/null 2>&1 || {
    echo "error: cargo not found in PATH (install Rust 1.85+ from https://rustup.rs)" >&2
    exit 1
}
command -v npm >/dev/null 2>&1 || { echo "error: npm not found in PATH (install Node.js 24+)" >&2; exit 1; }

echo "==> Building OpenDots web app"
(cd "$WEB_DIR" && npm ci && npm run build)

echo "==> Building dibi-aether (release)"
cargo build --release

BIN="$PROJECT_DIR/target/release/aether"
if [[ ! -x "$BIN" ]]; then
    echo "error: expected binary not found at $BIN" >&2
    exit 1
fi

echo "==> Assembling portable bundle in $DIST_DIR"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

install -Dm755 "$BIN" "$DIST_DIR/AETHER"
install -Dm644 "$PROJECT_DIR/packaging/aether.desktop" "$DIST_DIR/AETHER.desktop"

WEB_BUNDLE="$DIST_DIR/AETHER-web"
mkdir -p "$WEB_BUNDLE"
cp "$WEB_DIR/package.json" "$WEB_DIR/package-lock.json" "$WEB_BUNDLE/"
cp -R "$WEB_DIR/dist" "$WEB_BUNDLE/dist"
(cd "$WEB_BUNDLE" && npm ci --omit=dev)

cat > "$DIST_DIR/run.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$HERE/AETHER" "$@"
EOF
chmod 755 "$DIST_DIR/run.sh"

cat > "$DIST_DIR/README.txt" <<'EOF'
dibi AETHER (portable Linux bundle)
===================================

Run:
  ./AETHER

The app starts the OpenDots Node server on 127.0.0.1:4310 and stops it on exit.
The bundled OpenDots server and web app are included in AETHER-web/.

Requirements: Node.js 24+ on PATH, an X11 or Wayland desktop session, XKB,
OpenGL, ALSA, and Opus runtime libraries. Configure the bundled server's
provider credentials and options in AETHER-web/.env as needed. Voice calls
use the system default microphone and speaker.

Environment overrides:
  OPENDOTS_ROOT   Override the bundled OpenDots root (contains package.json and dist/)
  AETHER_URL      Attach to an existing server instead of starting one
  AETHER_PORT     Port for the local server (default 4310; PORT also works)
  OWNER_TOKEN     Owner token forwarded to the server

Log:
  ${XDG_DATA_HOME:-$HOME/.local/share}/dibi-aether/server.log

Desktop entry:
  cp AETHER.desktop ~/.local/share/applications/
  # Edit Exec in the installed desktop file to the absolute path to AETHER.
EOF

echo "==> Built $DIST_DIR"
echo "    Run: $DIST_DIR/run.sh"

mkdir -p "$RELEASE_DIR"
tar -czf "$RELEASE_DIR/AETHER-linux-v${VERSION}.tar.gz" -C "$(dirname "$DIST_DIR")" linux
echo "    Archive: $RELEASE_DIR/AETHER-linux-v${VERSION}.tar.gz"
