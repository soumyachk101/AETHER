# AETHER Swift desktop app

AETHER is a native desktop shell for the OpenDots web app. It starts the local
Node server when needed, embeds it in the platform webview, and stops only the
server process it started.

## Requirements

- macOS 13 or later, Xcode Command Line Tools, and Swift 5.9 or later.
- Windows 10/11, a Windows SwiftPM toolchain with the MSVC C++ workload, the
  Microsoft Edge WebView2 Evergreen Runtime, Node.js 24 or later, and network
  access to download the WebView2 SDK during the first build.
- Linux with Swift 5.9 or later, GTK 3, WebKitGTK 4.1, libsoup 3, and Node.js
  24 or later. On Debian/Ubuntu install `libgtk-3-dev libwebkit2gtk-4.1-dev
  libsoup-3.0-dev libjavascriptcoregtk-4.1-dev pkg-config`.
- The OpenDots web app in `AETHER-web/`. Run `npm ci` there before starting
  AETHER; it builds the web app automatically when its server output is absent.

## Build

Run the native-host script from any working directory:

```sh
# macOS
AETHER-swift/scripts/build-macos.sh

# Linux
AETHER-swift/scripts/build-linux.sh
```

On Windows, run in PowerShell:

```powershell
.\AETHER-swift\scripts\build-windows.ps1
```

The first Windows build downloads the official `Microsoft.Web.WebView2` NuGet
SDK into `AETHER-swift/.build/dependencies/Microsoft.Web.WebView2`. If the SDK
is already installed elsewhere, set `WEBVIEW2_SDK_DIR` to its extracted package
directory before running both the installer and build script.

Set `CONFIGURATION=debug` to build a debug configuration; the default is
`release`. SwiftPM builds native artifacts, so run each script on its target
operating system.

## Output and runtime

- macOS: `dist/macos/AETHER.app`; open it with `open dist/macos/AETHER.app`.
- Windows: `dist/windows/AETHER.exe`.
- Linux: `dist/linux/AETHER`.

All platforms need Node.js 24+ and a built or buildable OpenDots app root.
Set `OPENDOTS_ROOT` if `AETHER-web/` is not discoverable from the current
directory or executable. Set `AETHER_URL` or `OPENDOTS_URL` to attach to an
already running server. `AETHER_PORT` (or `PORT`) selects the default local
server port; it is `4310`. Set `OWNER_TOKEN` when the server requires an owner
token. A token in the app root's `.env` is also forwarded to the embedded page.

Server logs are written to `~/Library/Logs/dibi AETHER/server.log` on macOS,
`%LOCALAPPDATA%\dibi-aether\server.log` on Windows, and
`$XDG_STATE_HOME/dibi-aether/server.log` on Linux (default
`~/.local/state/dibi-aether/server.log`).

The macOS bundle is ad hoc signed for local launch when `codesign` is
available; it is not a Developer ID distribution signature. Windows requires
the WebView2 runtime on the target machine. Linux dynamically links GTK 3 and
WebKitGTK 4.1, which must be installed on the target machine.
