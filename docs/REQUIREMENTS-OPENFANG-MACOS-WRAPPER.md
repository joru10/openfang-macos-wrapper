# Requirements & Specification
## macOS App Wrapper for OpenFang + Loose OpenClaw Integration + GitHub Repo Delivery

## 1. Purpose
Build a native macOS app that provides manual lifecycle control for OpenFang and loose integration with OpenClaw GW (running in Docker) through shared channels/webhooks (Option A).

The app must:
- Start/stop OpenFang on demand.
- Provide status and logs.
- Open the OpenFang dashboard.
- Provide integration hooks so OpenFang outputs can be routed to OpenClaw-consumed channels/webhooks without shared product UI.

## 2. Target Environment
- macOS 13+ (Ventura).
- Apple Silicon and Intel (universal build preferred).
- OpenClaw GW runs in Docker on the same Mac (or reachable via LAN), but is not controlled by this app.

## 3. Assumptions / Constraints
- OpenFang is installed locally and available as CLI binary `openfang`.
- Dashboard is available at `http://localhost:4200` when OpenFang is running.
- OpenClaw GW provides message/workflow intake via webhook and/or shared channel.
- The app does not embed OpenClaw UI; it only supports OpenFang output routing into OpenClaw-accessible ingestion paths.

## 4. Definitions
- **Option A (loose integration):** OpenFang runs continuously/scheduled and pushes alerts/briefs to channel/webhook; OpenClaw is the interactive follow-up interface.
- **OpenClaw GW:** OpenClaw gateway/service running in Docker that connects channels and routes messages.

## 5. User Stories
1. Launch app, click Start, OpenFang runs, dashboard becomes available.
2. Click Open Dashboard to open `http://localhost:4200`.
3. Configure integration target (Slack/Discord/generic webhook) so outputs land where OpenClaw is present.
4. Click Stop to stop OpenFang.
5. On quit while running, choose stop/leave-running/cancel.
6. View logs and copy for troubleshooting.

## 6. Functional Requirements

### FR-1: Start OpenFang
- UI Start button.
- On Start:
  - Verify OpenFang binary path (FR-6).
  - If needed, offer `openfang init`.
  - Execute `openfang start` asynchronously.
  - Capture stdout/stderr to file and UI.
  - State transition: `Stopped -> Starting -> Running` after health check success.

### FR-2: Stop OpenFang
- UI Stop button.
- Stop order:
  1. Run `openfang stop` if supported.
  2. Else gracefully terminate tracked process.
  3. Else fallback: identify listener on `4200` and terminate only if it matches configured OpenFang executable path/signature.
- State transition: `Running -> Stopping -> Stopped`.

### FR-3: Open Dashboard
- UI Open Dashboard button.
- If Running, open configured dashboard URL (default `http://localhost:4200`) in default browser.
- If Stopped, prompt to Start.

### FR-4: Status & Health Check
- States: `Stopped`, `Starting`, `Running`, `Stopping`, `Error`, plus `Running (external)` when detected.
- Health probe: HTTP GET `http://127.0.0.1:4200/` (host/port configurable).
- Polling cadence:
  - Starting: every 1-2s.
  - Running: every 5-10s.

### FR-5: Logs
- Log file path: `~/Library/Logs/OpenFangWrapper/openfang.log`.
- UI shows tail of last N lines (default 1000, configurable).
- Actions: Copy Logs, Reveal in Finder.

### FR-6: OpenFang Binary Discovery & Configuration
- Auto-discovery order:
  - `/opt/homebrew/bin/openfang`
  - `/usr/local/bin/openfang`
  - PATH query via `/bin/zsh -lc 'which openfang'`
- If not found, allow file picker.
- Persist chosen path in UserDefaults.
- Editable in Settings.

### FR-7: Process Management
- Track PID started by app.
- Start is idempotent (no duplicate process spawn).
- If OpenFang is already running but external:
  - Show `Running (external)`.
  - Offer `Adopt control` only when safe; otherwise leave unmanaged.

### FR-8: Quit Behavior
- On quit while Running, prompt:
  - Stop and Quit
  - Leave Running and Quit
  - Cancel
- Optional “Don’t ask again” setting.

### FR-9: Integration Configuration (Channel/Webhook Targets)
- Integrations settings support one or more targets.
- Minimum support:
  - Generic webhook (HTTP POST): URL, headers, optional secret/token (Keychain).
  - Payload format: JSON (default) and plain text.
  - Optional presets: Slack Incoming Webhook, Discord Webhook.
- Capabilities:
  - Persist settings.
  - Test Webhook button posts sample message (`OpenFang Wrapper test`) and shows HTTP status + response snippet.
- Boundary:
  - If OpenFang already has channel adapters, app focuses on configuring/verifying endpoints and documenting wiring.

### FR-10: OpenClaw GW Docker Awareness (Non-controlling)
- Optional settings field: OpenClaw GW URL.
- Reachability check via HTTP/TCP.
- No Docker container start/stop or Docker permission requirement.

### FR-11: Workflow Model for Loose Coupling
Document intended flow:
1. OpenFang runs Hands and emits brief/alert.
2. OpenFang posts to shared channel/webhook endpoint.
3. OpenClaw consumes and handles follow-up interaction.

README must include `OpenFang -> webhook/channel -> OpenClaw GW` wiring section.

### FR-15: Mandatory Event Forwarding Chain
For Jose delivery, enforce this chain:
1. OpenFang emits update (brief/alert/delta/digest).
2. OpenFang POSTs update to OpenClaw GW ingestion webhook.
3. OpenClaw GW transforms/routes to Telegram outbound.
4. Jose receives via OpenClaw Telegram bot.

This remains Option A loose coupling.

### FR-16: OpenClaw GW Ingestion Endpoint (Incoming Webhook)
- Configurable ingestion URL in wrapper settings.
- Secret/token support:
  - Header (e.g., `X-Webhook-Secret`) and/or token query parameter.
  - Fail closed on secret mismatch/missing.
- Response behavior:
  - 2xx = accepted.
  - Non-2xx should trigger retry behavior (if available in OpenFang) and always surface error in logs.

### FR-17: Telegram Delivery via OpenClaw (Outbound)
- Telegram token/chat routing belongs to OpenClaw GW configuration, not wrapper app.
- Automatic delivery without manual approval.
- Telegram message should include:
  - Topic label
  - Timestamp
  - Severity (`info`/`alert`)
  - Summary and optional links

### FR-18: Message Contract (OpenFang -> OpenClaw)
Stable JSON payload schema (minimum):
```json
{
  "source": "openfang",
  "hand": "collector",
  "topic": "...",
  "severity": "info",
  "title": "...",
  "summary": "...",
  "bullets": ["..."],
  "links": [{ "title": "...", "url": "https://..." }],
  "timestamp": "2026-02-26T12:00:00Z",
  "dedupe_key": "..."
}
```
- `summary` target max length: 1500 chars.
- OpenClaw formatting must be deterministic.

### FR-19: Dedupe and Rate Control
- Dedupe by `dedupe_key` when present.
- Fallback dedupe hash of `(hand, title, primary link)`.
- Default dedupe window: 2 hours.
- Telegram rate limit default: max 1 message/minute, burst 3.

### FR-20: End-to-End Test Button (OpenClaw -> Telegram)
- Integrations screen includes `Test E2E (OpenClaw -> Telegram)`.
- Test action:
  - POST sample payload to OpenClaw ingestion endpoint.
  - Confirm HTTP 2xx.
  - Show best-effort user prompt/ack for Telegram receipt.
- Direct Telegram verification is optional unless Telegram API creds are stored (not required).

### FR-21: Docker Networking Guidance (Docs)
README must include one recommended wiring path for host OpenFang to Docker OpenClaw:
- Option 1 (macOS Docker Desktop typical):
  - OpenClaw publishes host port (e.g., `http://127.0.0.1:<port>/openfang-webhook`).
  - OpenFang posts to loopback.
- Option 2:
  - If OpenFang is containerized too, use Docker network DNS.

README must explicitly document:
- OpenClaw exposed port
- Ingestion path
- Required secret header
- Where Telegram bot token and `chat_id` are configured in OpenClaw

### FR-22: Explicit Scope Boundary
- Wrapper app responsibilities:
  - OpenFang lifecycle
  - OpenClaw ingestion URL/secret storage
  - Endpoint/E2E test utilities
- OpenClaw GW responsibilities:
  - Routing and Telegram outbound delivery
- OpenFang responsibilities:
  - Producing update events/payloads

## 8. Non-Functional Requirements
- Responsive UI; all process/network operations async.
- No admin privileges required.
- Secrets in Keychain.
- Safe stop semantics; never kill unrelated process on port conflicts.
- Internal separation:
  - `OpenFangController`
  - `HealthChecker`
  - `LogManager`
  - `IntegrationManager`

## 9. UI Requirements (MVP)
Main window:
- Status indicator (dot + text)
- Buttons: Start, Stop, Open Dashboard
- Log tail panel
- Footer with OpenFang binary path

Settings tabs:
- General
  - OpenFang binary path
  - Dashboard URL
  - Quit behavior
  - Log lines shown
- Integrations
  - Webhook target list (add/edit/delete)
  - Test webhook button
  - OpenClaw GW URL + reachability check
  - Test E2E (OpenClaw -> Telegram)

## 10. Technical Specification
- Swift + SwiftUI.
- Use `Process` for OpenFang lifecycle commands, capture `stdout`/`stderr` via `Pipe`.
- Health checks via `URLSession` with short timeout.
- Serialized log writes, throttled UI tail updates.
- Keychain wrapper for secrets.

Stop strategy:
- Prefer `openfang stop`.
- Else terminate tracked PID after executable verification.
- Fallback uses:
  - `lsof -iTCP:4200 -sTCP:LISTEN -n -P`
  - Validate executable path contains configured OpenFang binary path
  - Then SIGTERM/SIGKILL as last resort

Architecture policy:
- OpenFang may support direct Telegram adapters, but for Jose delivery that path is disabled by policy.
- **OpenClaw is the sole Telegram sender** in this integration model.

## 11. GitHub Delivery Requirements (joru10)

### FR-12: Repo Creation and Structure
Repository (suggested name: `openfang-macos-wrapper`) must include:
- Xcode project
- `README.md` (setup, usage, troubleshooting)
- `LICENSE` (MIT unless otherwise specified)
- `.gitignore` for Xcode/Swift

### FR-13: Clone + Repo Workflow
Deliver exact commands for:
- Initialize local git repo
- Add remote for `github.com/joru10/<repo-name>`
- Push `main`

If repo already exists, include add-remote/push flow.
Recommend semantic tags (`v0.1.0`, etc.).

### FR-14: Build & Run Instructions
README must include:
- Prereq: OpenFang installed and initialized (`openfang init`)
- Build in Xcode
- Run instructions
- Log file path
- OpenFang binary path configuration
- Webhook and OpenClaw GW URL testing

## 12. Acceptance Criteria
- App launches and detects OpenFang binary or prompts for selection.
- Start transitions to Running via health check.
- Dashboard opens expected URL.
- Stop reliably halts OpenFang.
- Quit prompt works and respects choice.
- Logs stream, copy, and reveal all work.
- Integrations can store webhook target and show successful test status.
- E2E test posts to OpenClaw and supports Telegram receipt confirmation workflow.
- Repository is complete, builds cleanly, and can be pushed to `joru10` with provided commands.

## 13. Out of Scope
- Deep API-level coupling between OpenFang and OpenClaw.
- Docker/container orchestration from wrapper app.
- Bundling OpenFang inside app.
- Authoring/editing OpenFang Hands in wrapper.
