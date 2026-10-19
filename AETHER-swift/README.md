# AETHER for macOS

AETHER is a native SwiftUI desktop client for OpenDots. It talks to the
OpenDots JSON API over HTTP and does not embed or render the web app.

## Requirements

- macOS 13 or later, Xcode Command Line Tools, and Swift 5.9 or later.
- Node.js 24 or later and the OpenDots app in `AETHER-web/` to start a local
  server. Run `npm ci` in that directory before launching AETHER.

## Build

```sh
AETHER-swift/scripts/build-macos.sh
```

The app bundle is written to `AETHER-swift/dist/macos/AETHER.app`.

## Runtime

AETHER discovers `AETHER-web/`, builds it with `npm run build` when the server
entry point is missing, starts the server on `127.0.0.1:4310`, and stops only
the process it started when the app exits. Choose the project folder and port
in Settings. Set `OPENDOTS_ROOT` to select a project folder, or set
`AETHER_URL`/`OPENDOTS_URL` to attach to an existing server.

The native client loads `/api/state` and `/api/workspace`, creates
conversations through `/api/conversations`, and manages tasks through
`/api/tasks` and task action routes. Enter the server's owner token in the
client when prompted; AETHER sends it as `Authorization: Bearer …` and stores
it in this Mac user's preferences. `OWNER_TOKEN` from the environment or the
project `.env` is read for API access and passed to the local server.

Server output is stored at `~/Library/Logs/dibi AETHER/server.log`.

The native client currently supports conversation selection and creation,
task listing and creation, refresh, and task run/pause actions. Other OpenDots
experiences, including chat turns, Spaces, integrations, and voice, are not
exposed in this desktop client.
