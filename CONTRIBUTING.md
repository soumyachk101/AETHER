# Contributing to AETHER

Thank you for your interest in contributing to **AETHER**! We welcome community contributions, bug reports, feature suggestions, and improvements across our entire ecosystem.

---

## Code of Conduct

All contributors and participants are expected to uphold our [Code of Conduct](CODE_OF_CONDUCT.md). Please read it before participating in discussions or submitting pull requests.

---

## Monorepo Architecture

AETHER is organized as a monorepo containing three core components:

| Component | Technology Stack | Purpose |
|---|---|---|
| **[AETHER-web](AETHER-web/)** | React 19, TipTap, Hono, CopilotKit, SQLite | Core web workspace, agent engine, server runtime |
| **[AETHER-swift](AETHER-swift/)** | Swift 5.9+, AppKit, WKWebView | Native macOS desktop application shell |
| **[AETHER-rust](AETHER-rust/)** | Rust 1.85+, Wry, Tao | Cross-platform desktop shell (Windows, Linux, macOS) |
| **[docs](docs/)** | Markdown | Centralized architectural, setup, and deployment guides |

---

## Getting Started

### Prerequisites

- **Node.js**: `v22.0.0` or later (tested on v24+)
- **npm**: `v10.0.0` or later
- **Rust**: `1.85+` with `cargo` (for `AETHER-rust`)
- **Swift / Xcode**: Swift 5.9+ / Xcode 15+ (macOS only, for `AETHER-swift`)
- **Docker**: Optional, required for isolated Docker sandbox computers (`AETHER-web`)

### Setting Up Development Environments

#### 1. Web Workspace (`AETHER-web`)

```bash
cd AETHER-web
npm install
cp .env.example .env
npm run dev
```

The web server will run on `http://localhost:3000`.

#### 2. macOS Desktop Shell (`AETHER-swift`)

```bash
cd AETHER-swift
# Build the native app bundle
./scripts/build-macos.sh
# Open the compiled app
open dist/macos/AETHER.app
```

#### 3. Cross-Platform Desktop Shell (`AETHER-rust`)

```bash
cd AETHER-rust
cargo build
cargo run
```

---

## Development Workflow

### 1. Branch Naming Conventions

Create a topic branch from `main`:

```bash
git checkout -b <type>/<short-description>
```

Common branch prefixes:
- `feat/`: New features or enhancements
- `fix/`: Bug fixes
- `docs/`: Documentation additions or revisions
- `refactor/`: Code reorganization without behavior change
- `test/`: Adding or improving test suites
- `chore/`: Build, tooling, or dependency updates

### 2. Testing & Quality Checks

Before submitting changes, ensure all tests and linter suites pass:

#### For `AETHER-web`:
```bash
cd AETHER-web
npm run typecheck
npm test
npm run format:check  # or npm run format to auto-format
```

#### For `AETHER-rust`:
```bash
cd AETHER-rust
cargo clippy --all-targets --all-features
cargo test
cargo fmt --check
```

#### For `AETHER-swift`:
```bash
cd AETHER-swift
swift test
swift build
```

---

## Submitting a Pull Request

1. **Commit Messages**: Write clear, descriptive commit messages adhering to Conventional Commits:
   - `feat: add voice waveform visualizer to macOS shell`
   - `fix: resolve race condition during SQLite WAL sync`
   - `docs: update sandbox computer setup instructions`
2. **Review Changes**: Verify that no credentials, `.env` files, or unintended binaries are included in your commit.
3. **Open a Pull Request**: Submit your PR targeting the `main` branch. Provide a clear summary of changes, motivation, and verification steps.

---

## Reporting Issues & Security Vulnerabilities

- **Bug Reports & Feature Requests**: Please use [GitHub Issues](https://github.com/soumyachk101/AETHER/issues).
- **Security Vulnerabilities**: Please review our [Security Policy](SECURITY.md) and report vulnerabilities privately.

---

## Maintainer

**Soumya Chakraborty** ([@soumyachk101](https://github.com/soumyachk101))
- Email: `soumya.chk101@gmail.com`
- Repository: [https://github.com/soumyachk101/AETHER](https://github.com/soumyachk101/AETHER)
