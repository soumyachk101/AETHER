# Security Policy

## Supported Versions

Security updates and patches are actively applied to the latest release on the `main` branch.

| Version | Supported |
| ------- | --------- |
| 0.1.x   | Yes       |
| < 0.1   | No        |

---

## Reporting a Vulnerability

The AETHER team takes security seriously. If you discover a security vulnerability within AETHER, please follow responsible disclosure guidelines.

### How to Report

**Please do NOT report security vulnerabilities via public GitHub issues.**

Instead, please send an encrypted or direct email to:
- **Maintainer**: Soumya Chakraborty
- **Email**: `soumya.chk101@gmail.com`
- **Subject Line**: `[SECURITY VULNERABILITY] AETHER - <Brief Summary>`

### What to Include

To help us triage and resolve the issue quickly, please provide:
1. A clear description of the vulnerability.
2. Steps to reproduce the issue (including any sample payloads, configurations, or reproduction scripts).
3. The affected component (`AETHER-web`, `AETHER-swift`, `AETHER-rust`, or Docker supervisor).
4. Potential impact or threat vectors.
5. Any suggested fixes or mitigations if available.

### Disclosure Timeline

- **Acknowledgment**: You will receive an initial response acknowledging receipt within 48 hours.
- **Assessment**: We will evaluate the report and confirm the vulnerability within 5 business days.
- **Resolution**: We will prepare, test, and release a patch as quickly as possible.
- **Public Disclosure**: Once a patch is released, a public security advisory will be published, crediting the reporter (unless you request anonymity).

---

## Security Architecture Principles

AETHER incorporates several defensive security boundaries:

1. **Loopback-Only Bindings**: By default, the local HTTP and WebSocket servers bind strictly to `127.0.0.1` / `::1` to prevent unauthenticated network access.
2. **Docker Sandboxing**: Agent computer sandboxes execute in isolated Docker containers with non-root execution, dropped Linux capabilities (`cap_drop: [ALL]`), and security options (`no-new-privileges:true`).
3. **Cryptographic Token Verification**: Computer supervisor APIs require HMAC-SHA256 authenticated tokens (`x-aether-bot-id`), and cannot be accessed without the configured master secret.
4. **Environment Isolation**: Sensitive secrets (OpenAI / Anthropic / Groq API keys) are stored locally in `.env` files which are strictly excluded from source control.
