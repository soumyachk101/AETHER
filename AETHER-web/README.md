# AETHER Web Workspace

**AETHER Web** is the core self-hosted personal-agent workspace and intelligence hub of the [AETHER](https://github.com/soumyachk101/AETHER) platform, created by [Soumya Chakraborty](https://github.com/soumyachk101).

---

## Key Highlights

- **Full AI Workspace**: Interactive chat interface powered by CopilotKit Intelligence and OpenAI-compatible models.
- **TipTap Rich Text Documents**: Markdown-first document editor with live task lists, tables, and AI collaboration.
- **Specialist Dots**: Autonomous multi-agent orchestration for distinct workflows (coding, research, data analysis).
- **WebRTC Voice Support**: Low-latency realtime audio conversation capabilities.
- **Connected Services**: Integrated MCP (Model Context Protocol) and Composio tooling for GitHub, Slack, Gmail, and more.
- **Isolated Computer Tools**: Containerized headless/browser sandboxes with shell execution.

---

## Getting Started

### 1. Installation
```bash
npm ci
```

### 2. Environment Configuration
```bash
cp .env.example .env
```
Fill in your API keys (`OPENAI_API_KEY`, `INTELLIGENCE_API_KEY`, `OWNER_TOKEN`).

### 3. Run Development Server
```bash
npm run dev
```

### 4. Build for Production
```bash
npm run build
npm start
```

---

## Architecture & Integration

`AETHER-web` serves both standalone in modern web browsers and as the headless core embedded inside:
- [`AETHER-swift`](../AETHER-swift): Native macOS WKWebView desktop app with automatic server lifecycle management.
- [`AETHER-rust`](../AETHER-rust): Native cross-platform desktop shell (Windows, Linux, macOS) using `wry` and `tao`.

---

## Author & License

- **Author**: Soumya Chakraborty ([@soumyachk101](https://github.com/soumyachk101))
- **Repository**: [https://github.com/soumyachk101/AETHER](https://github.com/soumyachk101/AETHER)
- **License**: MIT
