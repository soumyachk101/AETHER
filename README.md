# AETHER

<div align="center">
  <h3>Next-Generation Self-Hosted Personal AI Agent Workspace & Native Desktop Ecosystem</h3>
  <p>Created by <strong>Soumya Chakraborty</strong> (<a href="https://github.com/soumyachk101">@soumyachk101</a>)</p>

  [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
  [![Node.js](https://img.shields.io/badge/Node.js-v24%2B-green.svg)](https://nodejs.org/)
  [![Rust](https://img.shields.io/badge/Rust-1.85%2B-orange.svg)](https://www.rust-lang.org/)
  [![Swift](https://img.shields.io/badge/Swift-5.9%2B-red.svg)](https://developer.apple.com/swift/)
</div>

---

## Overview

**AETHER** is a unified, self-hosted AI agent workspace and native desktop suite designed for deep focus, intelligence augmentation, and seamless agent orchestration. 

It provides complete parity across the web and native desktop platforms:
- 🌐 **[AETHER-web](AETHER-web/)**: The core web workspace featuring CopilotKit conversational AI, TipTap rich text documents & markdown editor, multi-agent Dots, MCP integrations, and isolated Docker sandbox computers.
- 🍏 **[AETHER-swift](AETHER-swift/)**: A native macOS desktop shell wrapping the workspace inside WKWebView with native menu shortcuts, audio/microphone permissions, and background Node.js server lifecycle management.
- 🦀 **[AETHER-rust](AETHER-rust/)**: A native cross-platform desktop shell for Windows, Linux, and macOS using `wry` and `tao`.

---

## Repository Structure

```
AETHER/
├── AETHER-web/       # Core web application (React 19, TipTap, Hono, CopilotKit, SQLite)
├── AETHER-swift/     # Native macOS desktop shell (Swift, AppKit, WKWebView)
├── AETHER-rust/      # Native cross-platform desktop shell (Rust, Wry, Tao)
└── docs/             # Technical documentation & setup guides
    ├── SETUP.md
    ├── SETUP-TELEMETRY.md
    └── COMPUTERS.md
```

---

## Core Capabilities

- **Autonomous Agent Dots**: Create specialist agents with tailored prompts, tool allowances, and persistent memories.
- **Rich Document Editor**: TipTap collaborative document environment supporting full markdown export, real-time agent editing, and structured page hierarchies.
- **Native Voice & Audio**: Low-latency WebRTC conversational voice channel directly inside the desktop shells and web interface.
- **Isolated Docker Sandboxes**: Run web browsers and execute terminal commands inside sandboxed container environments with owner oversight.
- **Extensible Integrations**: Support for MCP (Model Context Protocol), Composio account tools, Slack sockets, and Parallel web research.

---

## Quick Start

### 1. Web Application
```bash
cd AETHER-web
npm ci
cp .env.example .env
npm run dev
```

### 2. macOS Desktop Application
```bash
./AETHER-swift/scripts/build-macos.sh
open AETHER-swift/dist/macos/AETHER.app
```

### 3. Rust Cross-Platform Desktop App
```bash
cd AETHER-rust
cargo run --release
```

---

## Documentation

- 📖 [Setup & Installation Guide](docs/SETUP.md)
- 🔒 [Telemetry & Privacy Settings](docs/SETUP-TELEMETRY.md)
- 🖥️ [Agent Computers & Sandbox Architecture](docs/COMPUTERS.md)

---

## Author & Connect

- **Author**: Soumya Chakraborty
- **GitHub**: [@soumyachk101](https://github.com/soumyachk101)
- **Repository**: [https://github.com/soumyachk101/AETHER](https://github.com/soumyachk101/AETHER)

---

## License

This project is licensed under the [MIT License](LICENSE).
