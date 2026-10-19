# AETHER for macOS

AETHER is a native macOS SwiftUI desktop client for OpenDots. It supervises the local Node server on `127.0.0.1:4310` and uses the server's JSON API and CopilotKit stream directly. It does not embed a browser or web UI.

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

- **Native workspace**: Home, Dots, conversations, Spaces and pages, scheduled activity, memories, and settings are rendered with SwiftUI.
- **Workspace actions**: Create and edit Dots, create Spaces, search and manage pages, schedule and manage tasks, and add, edit, or remove memories.
- **Native chat**: Sends turns through the CopilotKit event stream and displays messages for the current app session.
- **Server Lifecycle Supervision**: Auto-discovers `AETHER-web/`, compiles artifacts with `npm run build` if missing, starts the local server on `127.0.0.1:4310`, and cleanly shuts down the child process on application termination.
- **Authentication**: Reads `OWNER_TOKEN` from `.env` or the environment and sends it as bearer authorization to the local API.
- **Native Desktop Menus & Shortcuts**:
  - `Cmd+Opt+R`: Restart local server
  - Open project folder in Finder
  - Reveal server log in Finder
- **Settings Scene**: Custom project root selection, port configuration, and live server logs.
- **Diagnostics & Error Recovery**: In-app console showing real-time server output with instant retry controls if the server fails to bind or exits.

Conversation history is not exposed by the server API, so chat messages are held in memory for the current app session. Voice, computer control, connected-service approvals, and the web page editor's advanced tools are not yet available in this native client.

## Server Output & Logs

Server output is streamed to:
`~/Library/Logs/dibi AETHER/server.log`
