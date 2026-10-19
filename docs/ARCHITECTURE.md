# AETHER System Architecture

AETHER is a unified, self-hosted AI agent workspace and native desktop ecosystem engineered for deep personal knowledge work, multi-agent orchestration, and seamless human-agent collaboration.

This document details the architectural principles, component structure, inter-process communication (IPC), and security model across the entire monorepo.

---

## High-Level Topology

```
+-------------------------------------------------------------------------+
|                              AETHER Ecosystem                           |
+-------------------------------------------------------------------------+
|                                                                         |
|  +--------------------+  +--------------------+                         |
|  |    AETHER-swift    |  |    AETHER-rust     |                         |
|  | (macOS Native App) |  | (Cross-Platform)   |                         |
|  | AppKit + WKWebView |  | Tao + Wry Webview  |                         |
|  +---------+----------+  +---------+----------+                         |
|            |                       |                                    |
|            +-----------+-----------+                                    |
|                        | (Local Loopback HTTP / WebSocket)              |
|                        v                                                |
|  +-------------------------------------------------------------------+  |
|  |                             AETHER-web                            |  |
|  |  +-------------------------------------------------------------+  |  |
|  |  |                    Frontend UI Layer (React 19)             |  |  |
|  |  | - TipTap Collaborative Rich Editor                          |  |  |
|  |  | - Multi-Agent Chat & Threads                                |  |  |
|  |  | - WebRTC Ambient Audio / Voice Studio                       |  |  |
|  |  | - Computer Sandbox Management UI                            |  |  |
|  |  +------------------------------+------------------------------+  |  |
|  |                                 | (Internal Fetch / EventStream)  |  |
|  |  +------------------------------v------------------------------+  |  |
|  |  |                   Backend Services (Hono / Node.js)         |  |  |
|  |  | - CopilotKit Intelligence & Agent Runtime                   |  |  |
|  |  | - Dot Agent Management Engine                               |  |  |
|  |  | - SQLite Document & Vector Store (WAL Mode)                 |  |  |
|  |  | - MCP Tool Broker & Composio Integration                    |  |  |
|  |  | - Slack Sockets & Telemetry Pipeline                        |  |  |
|  |  +------------------------------+------------------------------+  |  |
|  +---------------------------------|---------------------------------+  |
|                                    |                                    |
+------------------------------------|------------------------------------+
                                     | (Docker Engine Socket / Loopback HTTP)
                                     v
+-------------------------------------------------------------------------+
|                 Sandboxed Docker Computer Environment                   |
+-------------------------------------------------------------------------+
|  +-------------------------------------------------------------------+  |
|  |                     Computer Supervisor Daemon                     |  |
|  |  - Container Lifecycle Manager                                    |  |
|  |  - HMAC-SHA256 Token Gatekeeper                                   |  |
|  +-----------------------------------+-------------------------------+  |
|                                      |                                  |
|         +----------------------------+----------------------------+     |
|         v                                                         v     |
|  +-------------------------------+         +--------------------------+ |
|  |   Agent Sandbox Container A   |         | Agent Sandbox Container B| |
|  | - Chromium Browser Instance   |         | - Headless Environment   | |
|  | - Isolated Persistent Volumes |         | - Bash Tooling           | |
|  +-------------------------------+         +--------------------------+ |
+-------------------------------------------------------------------------+
```

---

## 1. Monorepo Modules

### A. `AETHER-web` (Core Workspace Engine)
- **Frontend Stack**: Built on React 19, Vite, Tailwind-compatible vanilla styling, and Lucide icons.
- **TipTap Rich Editor**: Provides document workspaces, block formatting, markdown sync, and agent-assisted collaborative drafting.
- **Backend Stack**: Built on Hono running inside Node.js 22+.
- **Database**: Embedded SQLite with WAL (Write-Ahead Logging) mode, enabling high-concurrency read/write operations for documents, chat history, agent definitions, and workspace configuration without external database dependencies.
- **Agent Intelligence**: Driven by CopilotKit runtime, supporting specialized agent personas ("Dots") equipped with memory, system prompt tailoring, and dynamic tool assignment.

### B. `AETHER-swift` (Native macOS Application)
- **Frameworks**: Native Swift 5.9+ with AppKit and WebKit (`WKWebView`).
- **Process Management**: Spawns and supervises the underlying Node.js workspace server (`ServerController.swift`), managing graceful startup, port resolution, and process termination on app exit.
- **macOS Integration**:
  - Native AppKit menu bar items and standard keyboard shortcuts (⌘N, ⌘W, ⌘Q, ⌘R).
  - WebRTC microphone permissions and media capture integration.
  - Native window restoration and dark/light system appearance sync.

### C. `AETHER-rust` (Cross-Platform Native Shell)
- **Frameworks**: Rust 1.85+ with `tao` (window management) and `wry` (cross-platform webview).
- **Portability**: Provides cross-platform desktop shells for Windows, Linux, and macOS without the overhead of heavy Electron bundles.
- **Features**: Local URL binding, clean system tray integration, and native accelerator hooks.

---

## 2. Agent "Dots" Architecture

Dots represent autonomous AI specialists within an AETHER workspace. Each Dot maintains:
1. **Persona & Instructions**: Tailored system prompts defining role, tone, and operational guidelines.
2. **Memory Ledger**: Persistent long-term memory records stored in the local SQLite database.
3. **Tool Access**: Granular permissioning for file system reading, web searches (via Parallel), MCP tools, and Docker sandbox execution.
4. **Thread Isolation**: Distinct conversational threads allowing asynchronous task progression without context pollution.

---

## 3. Computer Sandbox Architecture

When an agent needs to browse the web, test code, or interact with external services, it operates through an isolated Docker sandbox:

1. **Supervisor Pattern**: A lightweight supervisor container binds strictly to loopback (`127.0.0.1:4312`) and controls the Docker engine socket.
2. **Per-Dot Isolation**: Each agent Dot receives a dedicated, containerized sandbox with separate named volumes for filesystem artifacts and browser profiles.
3. **Cryptographic Authentication**: Requests between `AETHER-web` and the supervisor are signed using HMAC-SHA256 derived from a high-entropy master secret and the agent's unique identifier:
   ```
   Token = HMAC_SHA256(MasterSecret, "aether-computer:" + DotID)
   ```
4. **Hardened Containment**: Containers drop all Linux capabilities (`cap_drop: [ALL]`), disallow privilege escalation (`no-new-privileges:true`), and enforce strict memory limits.

---

## 4. Universal Design & Single Source of Truth

To maintain a clean open-source standard:
- **Licensing**: A single canonical [LICENSE](../LICENSE) file is located at repository root (MIT License under Soumya Chakraborty).
- **Documentation**: All architectural, installation, and deployment documentation lives centrally in [`docs/`](../docs/), preventing documentation drift across sub-packages.
- **Privacy First**: Telemetry is opt-out configurable via standard `DO_NOT_TRACK` or `COPILOTKIT_TELEMETRY_DISABLED` flags.
