# AETHER for macOS

AETHER is a native macOS Swift desktop application for OpenDots. It supervises the local OpenDots Node server on `127.0.0.1:4310` and renders the full OpenDots web application (threads, canvas, TipTap editor, voice, and CopilotKit intelligence) inside a native WebKit container with AppKit integration.

## Requirements

- macOS 13 or later, Xcode Command Line Tools, and Swift 5.9 or later.
- Node.js 24 or later and the OpenDots app in `AETHER-web/` to start the local server. Run `npm ci` and `npm run build` in `AETHER-web/`.

## Build

```sh
AETHER-swift/scripts/build-macos.sh
```

The application bundle is written to `AETHER-swift/dist/macos/AETHER.app`.

To run directly from source with SwiftPM:

```sh
cd AETHER-swift
swift run
```

## Features

- **Embedded Web Experience**: Hosts the complete OpenDots web interface with hardware acceleration and WebKit integration.
- **Server Lifecycle Supervision**: Auto-discovers `AETHER-web/`, compiles artifacts with `npm run build` if missing, starts the local server on `127.0.0.1:4310`, and cleanly shuts down the child process on application termination.
- **Seamless Authentication**: Automatically reads `OWNER_TOKEN` from `.env` or the environment and injects session credentials directly into the webview.
- **Native Desktop Menus & Shortcuts**:
  - `Cmd+R`: Reload current view
  - `Cmd+Shift+O`: Open in default system browser
  - `Cmd+Opt+R`: Restart local server
  - Open project folder in Finder
  - Reveal server log in Finder
- **Settings Scene**: Custom project root selection, port configuration, and live server logs.
- **Diagnostics & Error Recovery**: In-app console showing real-time server output with instant retry controls if the server fails to bind or exits.

## Server Output & Logs

Server output is streamed to:
`~/Library/Logs/dibi AETHER/server.log`
