# AETHER (Rust)

A native desktop shell for AETHER. It opens a `tao` window, embeds the
AETHER web workspace in the native OS webview (`wry`), starts the local Node server on
`127.0.0.1:4310`, and stops that server when the window closes.

The crate is named `aether`; the binary is `aether`. Platform packaging
renames the executable to `AETHER` (`AETHER.exe` on Windows).

## Prerequisites

### Windows

- Windows 10/11 with the Microsoft Edge WebView2 Evergreen Runtime installed
  on the target machine.
- Node.js 24 or newer.
- Rust 1.85+ with the MSVC toolchain (`rustup default stable-msvc`) and Visual
  Studio Build Tools with the C++ workload.
- The web app must be installed and built (run `npm ci && npm run build` in `AETHER-web/`).

### Linux

Install the WebKitGTK 4.1 development stack (Debian/Ubuntu):

```bash
sudo apt update
sudo apt install -y libwebkit2gtk-4.1-dev libgtk-3-dev \
  libsoup-3.0-dev libjavascriptcoregtk-4.1-dev \
  build-essential pkg-config
```

Then install Node.js 24+, Rust 1.85+, and build the web app as above
(`npm ci && npm run build` in `AETHER-web/`).

## Build and run

```bash
cd AETHER-rust
cargo run              # debug
cargo build --release  # release
./target/release/aether
```

`cargo run` locates the AETHER project root by walking up from the current directory
and the executable. If the app lives elsewhere, set `AETHER_ROOT` (see below).
AETHER starts the already-built server; it does not run `npm install`.

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `AETHER_ROOT` / `OPENDOTS_ROOT` | auto-detected | Absolute path to the AETHER app root (contains `package.json` and `src/server/index.ts`). |
| `AETHER_URL` / `OPENDOTS_URL` | `http://127.0.0.1:<port>/` | Attach to an already-running server instead of starting one. No child process is spawned or killed. |
| `PORT` / `AETHER_PORT` | `4310` | Port used for the embedded server and URL. `AETHER_PORT` is the AETHER-specific override. |
| `OWNER_TOKEN` | unset | Forwarded to the server environment when the instance requires an owner token. |

## How the server is supervised

1. Resolve the project root and verify it contains the built entry point
   `dist/server/server/index.js` and `node_modules/`.
2. If `AETHER_URL`/`OPENDOTS_URL` is set, poll that URL and attach read-only.
3. Otherwise spawn `node --env-file-if-exists=.env dist/server/server/index.js`
   with `HOST=127.0.0.1` and `PORT=<port>`, streaming stdout/stderr into the log.
4. Poll the URL until it answers (HTTP responses below 500 count as ready).
5. On window close or app exit, terminate the child process. A server that dies
   unexpectedly is reported in the UI and the log.

## Logs

- Windows: `%LOCALAPPDATA%\aether\server.log`
- Linux: `$XDG_DATA_HOME/aether/server.log` (normally
  `~/.local/share/aether/server.log`)
- macOS: `~/Library/Logs/aether/server.log`

The log contains server output plus AETHER lifecycle messages.

## Troubleshooting

- **"Could not find the AETHER project"** — set `AETHER_ROOT` to the
  directory containing the `package.json`.
- **Missing `dist` / entry point** — run `npm ci && npm run build` in `AETHER-web/`.
- **`node` not found** — GUI launches may not inherit your shell `PATH` on
  Linux. Start AETHER from a terminal, or put `node` on the system `PATH`
  (`/usr/local/bin`). Confirm with `node --version` (must be 24+).
- **WebKitGTK errors on Linux** — wry 0.57 needs WebKitGTK 4.1 and libsoup 3.
- **Port already in use** — set `AETHER_PORT` (or `PORT`) to a free port, or
  start the server yourself and use `AETHER_URL`.

## Native packaging

Build the web app first (`npm ci && npm run build` in `AETHER-web/`), then run
the platform script from this crate directory:

```bash
./scripts/build-linux.sh
```

```powershell
.\scripts\build-windows.ps1
```

Each script compiles a release binary and places a portable bundle under
`dist/<platform>/`. Launch `dist/linux/AETHER` on Linux or
`dist/windows/AETHER.exe` on Windows.

## Architecture

`main.rs` creates the `tao` event loop and window, then a `wry` WebView pointed
at the local URL. A server supervisor owns the Node child process and health
poll and is shut down on exit. `dirs` supplies the per-platform data directory
for logs; `webbrowser` opens external links. There is no separate Rust UI layer:
all UI is the AETHER web workspace itself.
