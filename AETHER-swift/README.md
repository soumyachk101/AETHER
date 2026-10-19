# AETHER Swift desktop app

AETHER is a native macOS desktop shell for the AETHER web workspace. It starts the local
Node server when needed, embeds it in native WKWebView, and stops only the
server process it started.

## Requirements

- macOS 13 or later, Xcode Command Line Tools, and Swift 5.9 or later.
- Node.js 24 or later and the web app in `AETHER-web/`. Run `npm ci` and `npm run build` in `AETHER-web/`.

## Build

Run the macOS build script:

```sh
AETHER-swift/scripts/build-macos.sh
```

The application bundle is written to `AETHER-swift/dist/macos/AETHER.app`.
Run it with:

```sh
open AETHER-swift/dist/macos/AETHER.app
```

To run directly from source with SwiftPM:

```sh
cd AETHER-swift
swift run
```

## Features

- **Full AETHER Workspace Experience**: Renders the exact UI and features of `AETHER-web` including CopilotKit conversational AI, TipTap rich text documents & markdown editor, Spaces, Pages, task activity, and connected services.
- **Native Chat & Voice**: Native WebRTC voice calls and media capture with microphone permissions automatically granted via WKWebView.
- **Server Lifecycle Supervision**: Auto-discovers `AETHER-web/`, compiles artifacts with `npm run build` if missing, starts the local server on `127.0.0.1:4310`, and cleanly shuts down the child process on application termination.
- **Authentication**: Reads `OWNER_TOKEN` from `.env` or the environment and injects it into `sessionStorage` at document start for instant authentication.
- **Native Desktop Menus & Shortcuts**:
  - `Cmd+R`: Reload web view
  - `Cmd+Shift+O`: Open current page in default browser
  - `Cmd+Opt+R`: Restart local server
  - Open project folder in Finder
  - Reveal server log in Finder
- **Settings Scene**: Custom project root selection, port configuration, and live server logs.
- **Diagnostics & Error Recovery**: In-app console showing real-time server output with instant retry controls if the server fails to bind or exits.

## Server Output & Logs

Server output is streamed to:
`~/Library/Logs/AETHER/server.log`
