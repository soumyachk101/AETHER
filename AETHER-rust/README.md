# dibi AETHER (Rust)

A small native desktop shell for OpenDots. It opens a `tao` window, embeds the
OpenDots web app in the OS webview (`wry`), starts the local Node server on
`127.0.0.1:4310`, and stops that server when the window closes.

The crate is named `dibi-aether`; the binary is `aether`. Platform packaging
renames the executable to `AETHER` (`AETHER.exe` on Windows).

## Prerequisites

### Windows

- Windows 10/11 with the Microsoft Edge WebView2 Evergreen Runtime installed
  on the target machine (usually preinstalled; otherwise install the Evergreen
  Runtime from Microsoft).
- Node.js 24 or newer.
- Rust 1.85+ with the MSVC toolchain (`rustup default stable-msvc`) and Visual
  Studio Build Tools with the C++ workload.
- The web app must be installed and built (run in the OpenDots app directory,
  i.e. the directory containing `package.json` with `"name": "opendots"` —
  `AETHER-web/` in this repository):

  ```powershell
  npm ci
  npm run build
  ```

### Linux

Install the WebKitGTK 4.1 development stack (Debian/Ubuntu):

```bash
sudo apt update
sudo apt install -y libwebkit2gtk-4.1-dev libgtk-3-dev \
  libsoup-3.0-dev libjavascriptcoregtk-4.1-dev \
  build-essential pkg-config
```

Then install Node.js 24+, Rust 1.85+, and build the web app as above
(`npm ci && npm run build`). On Fedora the equivalents are `webkit2gtk4.1-devel`,
`gtk3-devel`, `libsoup3-devel`, and `javascriptcoregtk4.1-devel`.

## Build and run

```bash
cd AETHER-rust
cargo run              # debug
cargo build --release  # release
./target/release/aether
```

`cargo run` locates the OpenDots root by walking up from the current directory
and the executable. If the app lives elsewhere, set `OPENDOTS_ROOT` (see below).
AETHER starts the already-built server; it does not run `npm install`.

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `OPENDOTS_ROOT` | auto-detected | Absolute path to the OpenDots app root (contains `package.json` with `name: opendots` and `src/server/index.ts`). |
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

- Windows: `%LOCALAPPDATA%\dibi-aether\server.log`
- Linux: `$XDG_DATA_HOME/dibi-aether/server.log` (normally
  `~/.local/share/dibi-aether/server.log`)

The log contains server output plus AETHER lifecycle messages.

## Troubleshooting

- **"Could not find the OpenDots project"** — set `OPENDOTS_ROOT` to the
  directory containing the `package.json` whose name is `opendots`.
- **Missing `dist` / entry point** — run `npm ci && npm run build` in the app
  directory. AETHER only serves what is already built.
- **`node` not found** — GUI launches may not inherit your shell `PATH` on
  Linux. Start AETHER from a terminal, or put `node` on the system `PATH`
  (`/usr/local/bin`). Confirm with `node --version` (must be 24+).
- **WebKitGTK errors on Linux** — wry 0.57 needs WebKitGTK 4.1 and libsoup 3.
  Ubuntu 22.04+ provides them; older releases need a newer distro or a
  source-built WebKitGTK. "libwebkit2gtk-4.0" mismatches mean 4.1 is missing.
- **White or blank window** — check the log for a failed server start. If the
  server is healthy, try `WEBKIT_DISABLE_COMPOSITING_MODE=1` (or
  `WEBKIT_DISABLE_DMABUF_RENDERER=1` on recent WebKitGTK) to rule out GPU
  driver issues, and verify `dist/client` assets were built.
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

Each script compiles the native Rust desktop executable and puts it in the
portable output directory `dist/linux/` or `dist/windows/`. The preserved
executable paths are `dist/linux/AETHER` and `dist/windows/AETHER.exe`. Linux
also includes `AETHER.desktop`, `run.sh`, and a `README.txt`; Windows includes
a `README.txt`. These are portable bundles, not installers. The executable
embeds the OS webview and controls the local OpenDots server.

Build OpenDots first by running `npm ci && npm run build` in `AETHER-web/`.
On the target machine, AETHER needs Node.js 24+ on its `PATH` and access to the
OpenDots app root containing `package.json`, `node_modules/`, and
`dist/server/server/index.js`. It starts that server on `127.0.0.1:4310` by
default and shuts down its child process on exit. Set `OPENDOTS_ROOT` to the
app root when auto-detection cannot find it. To attach to an already-running
OpenDots server/API, set `AETHER_URL` (or `OPENDOTS_URL`) to its URL; AETHER
does not spawn or stop that server. `PORT` or `AETHER_PORT` changes the local
server port, and `OWNER_TOKEN` is forwarded to the server when needed. The
bundle does not include Node.js, the OpenDots application, `node_modules`, or
the built `dist/`; provide them at a stable location on the target machine
and configure `OPENDOTS_ROOT`.

Linux build prerequisites are Rust 1.85+, `pkg-config`, and the WebKitGTK 4.1,
GTK 3, libsoup 3, and JavaScriptCoreGTK 4.1 development packages listed above.
Linux targets need those matching runtime libraries; the executable
dynamically links them. Windows build prerequisites are Rust 1.85+ with the
MSVC toolchain and Visual Studio Build Tools with the C++ workload. Windows
targets need the Microsoft Edge WebView2 Evergreen Runtime. Both target
platforms need Node.js 24+ and the built OpenDots app described above. No
installer or auto-updater is provided. Windows signing remains opt-in with
`-Sign`; it is skipped with a warning if the certificate or `signtool.exe` is
unavailable.

The Linux bundle includes `AETHER.desktop`; after copying it into
`~/.local/share/applications/`, set its `Exec` value to the absolute path of
the `AETHER` executable. The `packaging/aether.ico-placeholder.txt` documents
the optional Windows icon resource location; no icon is currently embedded.

## Architecture

`main.rs` creates the `tao` event loop and window, then a `wry` WebView pointed
at the local URL. A server supervisor owns the Node child process and health
poll and is shut down on exit. `dirs` supplies the per-platform data directory
for logs; `webbrowser` opens external links. There is no separate Rust UI layer:
all UI is the OpenDots web app itself.
