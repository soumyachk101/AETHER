#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist/linux"

cd "$PROJECT_DIR"

command -v cargo >/dev/null 2>&1 || {
    echo "error: cargo not found in PATH (install Rust 1.85+ from https://rustup.rs)" >&2
    exit 1
}

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
The web app must already be built (npm ci && npm run build in the OpenDots app
directory). If it lives elsewhere, set OPENDOTS_ROOT to its absolute path.

Requirements: WebKitGTK 4.1 (libwebkit2gtk-4.1), GTK 3, libsoup 3, Node.js 24+,
and the OpenDots dist/ output.

Environment overrides:
  OPENDOTS_ROOT   OpenDots project root (contains package.json and src/server/index.ts)
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
