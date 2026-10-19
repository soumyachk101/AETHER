# AETHER for Windows and Linux

AETHER is a native Rust desktop client for OpenDots. It draws its own native
desktop UI and uses the OpenDots JSON API; it does not embed a browser or load
the web app. The current client supports workspaces, Dot conversations, and
scheduled tasks.

The crate is named `dibi-aether`; its binary is `aether`. Packaging renames it
to `AETHER` on Linux and `AETHER.exe` on Windows.

## Requirements

Both platforms need Node.js 24 or later and a built OpenDots app. In
`AETHER-web/`, install dependencies and build it:

```sh
npm ci
npm run build
```

The app root must contain `package.json`, `node_modules/`, and
`dist/server/server/index.js`.

### Linux

Build with Rust 1.85 or later, `pkg-config`, a C/C++ build toolchain, and the
development libraries for X11, Wayland, XKB, and OpenGL. On Debian or Ubuntu:

```sh
sudo apt update
sudo apt install -y build-essential pkg-config libxkbcommon-dev \
  libwayland-dev libx11-dev libxcb1-dev libxrandr-dev libxi-dev \
  libxss-dev libxcursor-dev libxinerama-dev libxext-dev libxfixes-dev \
  libgl1-mesa-dev
```

On the target machine, AETHER needs an X11 or Wayland desktop session, working
OpenGL drivers, and Node.js 24+. It does not need GTK or WebKitGTK.

### Windows

Build on Windows 10 or 11 with Rust 1.85 or later, the MSVC Rust toolchain,
and Visual Studio Build Tools with the C++ workload. The target machine needs
Node.js 24+. AETHER uses its native Rust UI and does not need WebView2.

## Build and run

From this directory:

```sh
cargo run
cargo build --release
```

The app discovers `AETHER-web/` by walking up from its working directory and
executable. Set `OPENDOTS_ROOT` to the OpenDots app root when it lives
elsewhere. AETHER starts the already-built Node server and does not install
web dependencies.

## Settings and API access

| Variable | Default | Purpose |
| --- | --- | --- |
| `OPENDOTS_ROOT` | auto-detected | App root containing `package.json`, `node_modules/`, and the built server. |
| `AETHER_URL` / `OPENDOTS_URL` | `http://127.0.0.1:<port>/` | Connect to an existing OpenDots API server instead of starting one. |
| `AETHER_PORT` / `PORT` | `4310` | Port for the local server; `AETHER_PORT` takes precedence. |
| `OWNER_TOKEN` | unset | Bearer token for API access when OpenDots requires owner authentication. |

The client loads `/api/state` and `/api/workspace`, creates conversations
through `/api/conversations`, and manages tasks through `/api/tasks`. Enter an
owner token in the app when prompted. `OWNER_TOKEN` in the environment or
project `.env` is read for API access; the Node server also loads the project
`.env` when it starts.

The OpenDots API requires its model and intelligence settings to be configured
before a conversation or task can be created. Chat turns, Pages, integrations,
computer control, and voice are not part of this native client yet.

## Server lifecycle and logs

When no attach URL is set, AETHER starts
`node --env-file-if-exists=.env dist/server/server/index.js` with
`HOST=127.0.0.1` and the selected port. It stops only the child process it
started. If the server exits unexpectedly, AETHER displays an error and logs
the event.

- Windows: `%LOCALAPPDATA%\dibi-aether\server.log`
- Linux: `$XDG_DATA_HOME/dibi-aether/server.log` (normally
  `~/.local/share/dibi-aether/server.log`)

## Native packaging

Build on each target OS after building OpenDots:

```sh
./scripts/build-linux.sh
```

```powershell
.\scripts\build-windows.ps1
```

The outputs are `dist/linux/AETHER` and `dist/windows/AETHER.exe`. The Linux
bundle includes `AETHER.desktop`, `run.sh`, and a README; the Windows bundle
includes a README. These are portable bundles, not installers. Both require
the built OpenDots app and Node.js to remain available on the target machine.

Linux needs its desktop session and OpenGL drivers; Windows needs the MSVC
runtime installed with Visual Studio Build Tools when it is not already
present. No browser runtime, installer, or auto-updater is included.
