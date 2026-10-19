# dibi AETHER (Rust)

A native eframe/egui desktop client for OpenDots on Windows and Linux. It starts or attaches to the local Node server on `127.0.0.1:4310` and calls its JSON API directly. The interface does not use WebView, HTML, or browser fetch.

The crate is named `dibi-aether`; the binary is `aether`. Platform packaging renames the executable to `AETHER` (`AETHER.exe` on Windows).

## Prerequisites

### Windows

- Windows 10/11, Rust 1.85+ with the MSVC toolchain, and Visual Studio Build Tools with the C++ workload.
- CMake 3.15+ on `PATH` (the Opus audio codec is built from its bundled source).
- Node.js 24 or newer.
- The web app must be installed and built (run in the OpenDots app directory, i.e. `AETHER-web/`):

  ```powershell
  npm ci
  npm run build
  ```

### Linux

Install Rust 1.85+ and the X11 or Wayland desktop development dependencies required by eframe/winit. A desktop session with an OpenGL-capable graphics driver is required to run the app.

```bash
sudo apt update
sudo apt install -y build-essential cmake pkg-config libasound2-dev libopus-dev \
  libx11-dev libxkbcommon-dev libwayland-dev libegl1-mesa-dev
```

Then install Node.js 24+ and build the OpenDots app (`npm ci && npm run build` in AETHER-web/).

## Build and run

```bash
cd AETHER-rust
cargo run              # debug
cargo build --release  # release
./target/release/aether
```

`cargo run` locates the OpenDots root by walking up from the current directory and the executable. If the app lives elsewhere, set `OPENDOTS_ROOT` (see below). AETHER starts the already-built server; it does not run `npm install`.

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `OPENDOTS_ROOT` | auto-detected | Absolute path to the OpenDots app root (contains `package.json` with `name: opendots` and `src/server/index.ts`). |
| `AETHER_URL` / `OPENDOTS_URL` | `http://127.0.0.1:<port>/` | Use an already-running server without spawning or stopping its process. |
| `PORT` / `AETHER_PORT` | `4310` | Port used for the embedded server and URL. `AETHER_PORT` is the AETHER-specific override. |
| `OWNER_TOKEN` | unset | Forwarded to the server environment when the instance requires an owner token. |

## How the server is supervised

1. Resolve the project root and verify it contains the built entry point `dist/server/server/index.js` and `node_modules/`.
2. If `AETHER_URL`/`OPENDOTS_URL` is set, poll that URL and use its API without taking ownership of its process.
3. Otherwise spawn `node --env-file-if-exists=.env dist/server/server/index.js` with `HOST=127.0.0.1` and `PORT=<port>`, streaming stdout/stderr into the log.
4. Poll the URL until it answers (HTTP responses below 500 count as ready).
5. On window close or app exit, terminate the child process. A server that dies unexpectedly is reported in the UI and the log.

## Logs

- Windows: `%LOCALAPPDATA%\dibi-aether\server.log`
- Linux: `$XDG_DATA_HOME/dibi-aether/server.log` (normally `~/.local/share/dibi-aether/server.log`)

The log contains server output plus AETHER lifecycle messages.

## Native packaging

Build the web app first (`npm ci && npm run build` in `AETHER-web/`), then run the platform script from this crate directory:

```bash
./scripts/build-linux.sh
```

```powershell
.\scripts\build-windows.ps1
```

Each script compiles a release binary and places a portable bundle under `dist/<platform>/`. Launch `dist/linux/AETHER` on Linux or `dist/windows/AETHER.exe` on Windows. Each bundle includes a README with launch and environment-variable instructions. The app still needs access to the built OpenDots app root and its `node_modules`; set `OPENDOTS_ROOT` if the root is not auto-detected. Voice calls use the system default microphone and speaker. Linux builds need ALSA development files and the Opus runtime library; Windows builds link Opus statically and need CMake while building.

Linux targets need an X11 or Wayland session, XKB and OpenGL runtime libraries, and Node.js 24+ available on `PATH`. Windows targets need Node.js 24+ available on `PATH`; no WebView2 runtime is required. Both platforms need the built OpenDots app to start the local server. Windows signing remains opt-in with `-Sign`; it is skipped with a warning if the certificate or `signtool.exe` is unavailable.

The Linux bundle includes `AETHER.desktop`; after copying it into `~/.local/share/applications/`, set its `Exec` value to the absolute path of the `AETHER` executable.

## Architecture

`main.rs` creates a native eframe/egui window. API requests run on background threads so the UI remains responsive. A server supervisor owns any Node child process and stops it on exit. `dirs` supplies the per-platform data directory for logs.
