# AETHER Agent Computers

AETHER allows specialist AI Dots to operate isolated virtual computers. These computers allow agents to:
- Browse websites interactively with a full headless or visible Chromium browser.
- Read, write, and process files in persistent volumes.
- Execute bash/shell commands in a strictly isolated Linux sandbox.

---

## Security Model

Security is built into every layer of AETHER's computer execution environment:
- **Ephemeral Sandbox**: Each Dot is allocated its own dedicated container and isolated Docker network.
- **Rootless & Capability Dropped**: All Linux capabilities are dropped (`cap_drop: [ALL]`), and privileges cannot be escalated (`no-new-privileges:true`).
- **Owner Takeover & Approvals**: Sensitive shell operations, external network calls, or payments require explicit owner authorization.

---

## Setup & Running Computers

1. Configure secrets in `.env`:
   ```bash
   COMPUTER_SUPERVISOR_TOKEN=generate_random_secret_here_24chars
   COMPUTER_TOKEN=generate_second_random_secret_here_24chars
   COMPUTER_SUPERVISOR_URL=http://127.0.0.1:4312
   COMPUTER_NAMESPACE=aether
   ```

2. Start the computer supervisor service with Docker Compose:
   ```bash
   docker compose -f compose.yml -f compose.computers.yml up -d
   ```

3. In the AETHER workspace, navigate to the Dot settings and enable "Computer Tools". The Dot will now be able to request actions inside its virtual workspace.
