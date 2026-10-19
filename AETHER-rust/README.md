# dibi AETHER (Rust)

A native eframe/egui desktop client for OpenDots on Windows and Linux. It starts or attaches to the local Node server on `127.0.0.1:4310` and calls its JSON API directly. The interface does not use WebView, HTML, or browser fetch.

The crate is named `dibi-aether`; the binary is `aether`. Platform packaging renames the executable to `AETHER` (`AETHER.exe` on Windows).

## Prerequisites

### Windows

- Windows 10/11, Rust 1.85+ with the MSVC toolchain, and Visual Studio Build Tools with the C++ workload.
- CMake 3.15+ on `PATH` (the Opus audio codec is built from its bundled source).
- Node.js 24 or newer with npm. The packaging script installs, builds, and bundles the web app.

### Linux

Install Rust 1.85+ and the X11 or Wayland desktop development dependencies required by eframe/winit. A desktop session with an OpenGL-capable graphics driver is required to run the app.

```bash
sudo apt update
sudo apt install -y build-essential cmake pkg-config libasound2-dev libopus-dev \
  libx11-dev libxkbcommon-dev libwayland-dev libegl1-mesa-dev
```

Then install Node.js 24+ with npm. The packaging script installs and builds the OpenDots app.

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

Run the platform script from this crate directory. It runs `npm ci` and `npm run build` in the sibling `AETHER-web/`, then stages the web app's `package.json`, lockfile, `dist/`, and production dependencies beside the AETHER binary:

```bash
./scripts/build-linux.sh
```

```powershell
.\scripts\build-windows.ps1
```

Each script compiles a release binary and places a portable bundle under `dist/<platform>/`, plus a versioned archive under `dist/release/` (`AETHER-linux-v<VERSION>.tar.gz` or `AETHER-windows-v<VERSION>.zip`, using the crate version). Launch `dist/linux/run.sh` or `dist/windows/AETHER.exe`. The sibling `AETHER-web/` travels with the bundle, so the downloaded archive starts its API server without the source checkout or a separate web build. Node.js 24+ must be installed and available on `PATH`. Configure provider credentials and other server options in `AETHER-web/.env` before launch. `OPENDOTS_ROOT` can point AETHER at a different app root. Voice calls use the system default microphone and speaker. Linux builds need ALSA development files and the Opus runtime library; Windows builds link Opus statically and need CMake while building.

Local packaging requires Rust 1.85+, Node.js 24+ with npm, and the platform build dependencies listed above. Linux targets need an X11 or Wayland session, XKB and OpenGL runtime libraries. Windows targets need no WebView2 runtime. Windows signing remains opt-in with `-Sign`; it is skipped with a warning if the certificate or `signtool.exe` is unavailable.

The Linux bundle includes `AETHER.desktop`; after copying it into `~/.local/share/applications/`, set its `Exec` value to the absolute path of the `AETHER` executable.

## Architecture

`main.rs` creates a native eframe/egui window. API requests run on background threads so the UI remains responsive. A server supervisor owns any Node child process and stops it on exit. `dirs` supplies the per-platform data directory for logs.
