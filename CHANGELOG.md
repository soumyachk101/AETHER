# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.0] - 2026-10-19

### Added

- **Unified Monorepo Architecture**:
  - `AETHER-web`: Modern React 19 workspace with TipTap rich document editor, Hono backend runtime, and CopilotKit agent system.
  - `AETHER-swift`: Native macOS desktop shell leveraging AppKit and WKWebView with system menu integrations and background Node server lifecycle.
  - `AETHER-rust`: Cross-platform desktop shell utilizing Wry and Tao for Windows, Linux, and macOS.
- **Autonomous Agent Dots**:
  - Configurable AI specialists with customizable system instructions, tool access, and conversational memory.
  - Multi-agent coordination and thread management.
- **Dockerized Computer Sandboxes**:
  - Isolated browser and terminal execution per agent Dot.
  - Cryptographic HMAC-SHA256 supervisor token authentication.
  - Sandboxed execution profiles with non-privileged Linux containers.
- **Voice & Real-Time Interaction**:
  - WebRTC voice conversation channel with low-latency audio streaming.
  - Ambient speech transcription and audio controls.
- **Rich Document Editor**:
  - TipTap-based collaborative document environment supporting headings, code blocks, task lists, and markdown import/export.
- **Tooling & Integrations**:
  - Model Context Protocol (MCP) server support.
  - Composio tooling and third-party actions integration.
  - Slack socket channel integration.
  - Parallel public web research provider.
- **Universal Documentation & Licensing**:
  - Single canonical MIT License under Soumya Chakraborty.
  - Centralized technical guides in `docs/` (`SETUP.md`, `COMPUTERS.md`, `SETUP-TELEMETRY.md`, `ARCHITECTURE.md`).
  - Standard open-source community health files (`CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `SUPPORT.md`).
