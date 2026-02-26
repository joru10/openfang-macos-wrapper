# OpenFang macOS Wrapper (Option A)

Native SwiftUI macOS app wrapper for manual OpenFang lifecycle control with loose OpenClaw GW integration.

## Scope
- Starts/stops OpenFang CLI (`openfang start`, `openfang stop`)
- Health checks dashboard URL (`http://127.0.0.1:4200` default)
- Tails logs from `~/Library/Logs/OpenFangWrapper/openfang.log`
- Detects external OpenFang process and supports safe `Adopt Control`
- Configures/tests webhook targets
- Supports OpenClaw GW ingestion URL + E2E webhook test for Telegram forwarding

Policy for Jose delivery:
- OpenFang does **not** send Telegram directly.
- Mandatory chain: `OpenFang -> OpenClaw GW ingestion webhook -> Telegram`.
- OpenClaw is the sole Telegram sender.

## Prerequisites
- macOS 13+
- OpenFang installed and initialized:
  ```bash
  openfang init
  ```
- Full Xcode installed (for running GUI app), or at least Swift toolchain for package compile checks.

## Build and Run
1. Open in Xcode:
   - `apps/openfang-macos-wrapper/Package.swift`
2. Select target `OpenFangWrapperApp`.
3. Run.

CLI compile check:
```bash
cd apps/openfang-macos-wrapper
swift build
```

## Configuration
In app Settings:
- General:
  - OpenFang binary path
  - Dashboard URL
  - Quit behavior
  - Log lines shown
- Integrations:
  - Add/edit/delete webhook targets
  - Test Webhook
  - OpenClaw GW URL
  - Secret header + keychain account
  - Check GW Reachability
  - Test E2E (OpenClaw -> Telegram)

## OpenClaw Docker wiring
### Option 1 (host OpenFang, Docker OpenClaw on macOS)
- Publish OpenClaw port to host, e.g. `127.0.0.1:8787`
- Ingestion URL in wrapper:
  - `http://127.0.0.1:8787/openfang-webhook`
- Secret header:
  - `X-Webhook-Secret: <shared-secret>`

### Option 2 (both in Docker)
- Put OpenFang and OpenClaw on same Docker network.
- Use service DNS name for ingestion URL.

## Message Contract (OpenFang -> OpenClaw)
Minimum payload fields:
- `source`, `hand`, `topic`, `severity`, `title`, `summary`, `timestamp`
- optional: `bullets`, `links`, `dedupe_key`

## Troubleshooting
- Logs path:
  - `~/Library/Logs/OpenFangWrapper/openfang.log`
- If `start` fails:
  - verify OpenFang path in Settings
  - run `openfang init`
- If stop fallback is needed:
  - app validates process identity before killing listener on port 4200
- Quit behavior:
  - `Stop and Quit` now waits for stop completion before app termination

## GitHub delivery (private joru10/openfang)
If starting from this clone:
```bash
cd /Users/joru2/Applications/OpenFang/openfang

git remote add joru10-private https://github.com/joru10/openfang.git
# or update existing remote URL
# git remote set-url joru10-private https://github.com/joru10/openfang.git

git push -u joru10-private main

git tag -a v0.1.0 -m "OpenFang macOS wrapper initial scaffold"
git push joru10-private v0.1.0
```
