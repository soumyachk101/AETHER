# AETHER Setup Guide

This guide walks you through setting up and running **AETHER**, a self-hosted personal-agent workspace and desktop assistant created by Soumya Chakraborty ([soumyachk101](https://github.com/soumyachk101/AETHER)).

---

## Architecture Overview

AETHER consists of three primary components:
1. **`AETHER-web`**: The core web workspace (React 19, TipTap rich text documents, CopilotKit Intelligence, Hono backend, SQLite database).
2. **`AETHER-swift`**: The native macOS desktop wrapper embedding `AETHER-web` inside WKWebView with native menu shortcuts, audio/microphone permissions, and background Node.js server lifecycle management.
3. **`AETHER-rust`**: The native cross-platform desktop wrapper (Windows, Linux, macOS) powered by `wry` and `tao`, offering identical UI and features with native system integration.

---

## Prerequisites

- **Node.js**: v24.0.0 or later (with `npm`).
- **Rust**: 1.85+ (optional, for building the native `AETHER-rust` desktop shell).
- **macOS & Xcode Command Line Tools**: Swift 5.9+ (optional, for building the native `AETHER-swift` app).
- **Docker & Docker Compose**: (optional, for running containerized or isolated agent computers).

---

## 1. Quick Start (Web Workspace)

1. Clone the repository:
   ```bash
   git clone https://github.com/soumyachk101/AETHER.git
   cd AETHER/AETHER-web
   ```

2. Install dependencies:
   ```bash
   npm ci
   ```

3. Configure your environment:
   ```bash
   cp .env.example .env
   ```
   Open `.env` and configure your API keys:
   - `OPENAI_API_KEY`: Your OpenAI API key (or compatible endpoint via `OPENAI_BASE_URL`).
   - `INTELLIGENCE_API_KEY` (or `CPK_INTELLIGENCE_API_KEY`): CopilotKit Intelligence API key.
   - `OWNER_TOKEN`: A secure random token (24+ characters) if binding externally.

4. Start the development server:
   ```bash
   npm run dev
   ```
   Open [http://localhost:5173](http://localhost:5173) in your browser.

5. To build for production:
   ```bash
   npm run build
   npm start
   ```

---

## 2. Desktop Shells

### macOS Native App (`AETHER-swift`)
Run the macOS build script:
```bash
./AETHER-swift/scripts/build-macos.sh
open AETHER-swift/dist/macos/AETHER.app
```

### Cross-Platform Native Shell (`AETHER-rust`)
Build and run with Cargo:
```bash
cd AETHER-rust
cargo run --release
```

---

## 3. Integrations & Extensions

### Composio Tools
To enable real-world connected account tools (GitHub, Google, Slack, etc.):
1. Obtain an API key from [Composio](https://composio.dev).
2. Set `COMPOSIO_API_KEY=your_key` in `.env`.

### Voice & Real-Time Audio
AETHER supports real-time conversational voice agents over WebRTC:
1. Set `VOICE_API_KEY=your_key` in `.env`.
2. Configure `VOICE_MODEL` and `VOICE_NAME` (default: `marin`).

### Parallel Web Research
For live, real-time public web research:
1. Set `WEB_SEARCH_PROVIDER=parallel` (default).
2. Optionally supply `PARALLEL_API_KEY` in `.env` for production usage limits.

### Slack Channel Integration
To allow AETHER dots to listen and respond in your Slack workspace:
1. Set `SLACK_CHANNEL_NAME`, `SLACK_TEAM_ID`, and `SLACK_USER_IDS` in `.env`.
2. Run the application to establish the channel socket.

---

## 4. Docker Deployment

Deploy full stack with Docker Compose:
```bash
docker compose -f compose.yml up -d
```
The application will be accessible at [http://localhost:4310](http://localhost:4310).
