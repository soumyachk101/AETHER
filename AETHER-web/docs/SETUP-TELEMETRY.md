# AETHER Telemetry Configuration

AETHER respects user privacy and offers fine-grained controls over SDK telemetry reporting.

---

## Privacy by Design

AETHER separates user conversation data from diagnostic telemetry.
- **Conversations & Personal Data**: Your prompts, documents, memories, and files are stored strictly locally in your SQLite database (`DATABASE_PATH=data/aether.sqlite`) or within your private container instances. They are never sent to telemetry endpoints.
- **Diagnostic Telemetry**: Lightweight setup step events and runtime health markers are collected by the CopilotKit SDK to troubleshoot integration failures.

---

## Configuration & Opt-Out

You can adjust or completely disable telemetry at any time by configuring your `.env` file or environment variables:

### Complete Opt-Out
Set either of the following environment variables to `true` or `1`:
```bash
DO_NOT_TRACK=1
```
or
```bash
COPILOTKIT_TELEMETRY_DISABLED=true
```

### Telemetry Sampling
Control the sample rate between `0` (off) and `1` (100%):
```bash
COPILOTKIT_TELEMETRY_SAMPLE_RATE=1
```

---

## Offline Buffering & Resiliency

When telemetry is enabled, AETHER buffers up to 256 offline events locally in your SQLite database. If a network disruption occurs, events are retried with exponential backoff and delivered only when a connection is restored.
