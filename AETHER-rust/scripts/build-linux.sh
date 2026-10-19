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

echo "==> Building AETHER (native Rust release executable)"
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
AETHER (native Linux desktop bundle)
====================================

Run:
  ./AETHER

This bundle contains the native Rust desktop executable, not a web app or
Node.js runtime. It starts the OpenDots Node server on 127.0.0.1:4310 and
stops it on exit. Build OpenDots first (npm ci && npm run build in AETHER-web/).
The app root must include node_modules/ and dist/server/server/index.js. If it
is not discoverable beside this bundle, set OPENDOTS_ROOT to its absolute path.

Runtime requirements: WebKitGTK 4.1, GTK 3, libsoup 3, JavaScriptCoreGTK 4.1,
Node.js 24+ in PATH, and the built OpenDots app with node_modules/. The build
machine also needs the corresponding development packages, Rust 1.85+, and
pkg-config (see AETHER-rust/README.md).

Environment overrides:
  OPENDOTS_ROOT   OpenDots root (package.json, node_modules/, and dist/server/server/index.js)
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
echo "    Executable: $DIST_DIR/AETHER"
echo "    Launcher:   $DIST_DIR/run.sh"
