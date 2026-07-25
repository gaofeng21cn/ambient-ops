# Ambient Ops

Ambient Ops is a small self-hosted status aggregator and five-inch ambient
dashboard for a trusted local network. It combines privacy-preserving Codex
metrics pushed by each Mac with read-only UniFi WAN counters, then serves the
same normalized state to a browser or the dedicated HTC 5G Hub kiosk.

The display contains no metrics credentials or collection logic. It discovers
and opens the active Ambient Ops instance over the LAN.

## System

```text
Codex TPS apps -- authenticated aggregate snapshots --+
                                                       |
UDM-SE -------- SNMPv3 authPriv interface counters ----+--> Ambient Ops
                                                       |    Node server + React UI
/data ---------- normalized state and short history ---+          |
                                                                  +--> HTC kiosk
                                                                  +--> browsers
                                                                  +--> Home Assistant
                                                                       (optional)
```

The server, API, collector, discovery publisher, and built frontend ship as one
container. The Android kiosk is a separate native client. Codex TPS remains a
per-Mac agent because the raw Codex session files never leave their host.

Available surfaces:

- `GET /display/overview` - overview for the five-inch display
- `GET /display/network` - smoothed 4 Hz WAN chart and current rates
- `GET /display/machines` - per-machine Codex metrics and freshness
- `GET /display/pet` - selected host pet, token rates, and sessions
- `GET /display/eink` - low-motion, high-contrast e-ink view
- `GET /api/status` - normalized dashboard state
- `GET /metrics` - Prometheus text exposition
- `POST /api/v1/agents/:machineId/snapshot` - authenticated agent ingestion
- `GET /healthz` - process and source status

## Current deployment

The current canonical instance runs as a permanent macOS LaunchAgent. Live
UniFi SNMPv3 collection, Codex TPS push and pet state, Android LAN discovery,
immersive Home behavior, and recovery without `adb reverse` have been verified
on the physical HTC 5G Hub.

The next production step is a controlled move to Synology Docker. Do not run
the Mac and NAS instances as simultaneous discovery/ingestion owners. Preserve
the same `INSTANCE_ID` and agent token during the move so the HTC and Codex TPS
apps follow the new endpoint without becoming different logical installations.
See:

- [`HANDOFF.md`](HANDOFF.md) for the current release state
- [`docs/production-migration-checklist.md`](docs/production-migration-checklist.md)
  for the exact cutover, acceptance, and rollback sequence
- [`docs/deployment-synology.md`](docs/deployment-synology.md) for NAS setup

Home Assistant is an optional downstream bridge and is not required for
collection, display, or migration.

## Demo quick start

```bash
cp .env.example .env
mkdir -p secrets
openssl rand -hex 32 > secrets/agent_push_token
docker compose up --build -d
curl -fsS http://127.0.0.1:8787/healthz
```

Open `http://127.0.0.1:8787/display/overview`. The example defaults to
`DEMO_MODE=true` and disables mDNS discovery, so a developer container cannot
silently compete with the production instance.

For live operation, set `DEMO_MODE=false` and configure SNMPv3 as documented in
[`docs/unifi.md`](docs/unifi.md). A UniFi API key is not required when SNMPv3
is used. Linux/Synology production uses the host-network Compose override so
`_ambient-ops._tcp.local` reaches physical LAN clients.

## Deployment rules

- Exactly one canonical instance owns discovery and agent ingestion per site.
- Keep `INSTANCE_ID` stable across host, address, and port changes.
- Keep the same `AGENT_PUSH_TOKEN` or deliberately reconfigure every agent.
- Persist `/data`; never use `docker compose down -v` during an upgrade.
- Treat `healthz.ok=true` as process health only. Production acceptance also
  requires `mode=live`, live network and Codex sources, and the expected
  machine count.
- Store secrets in ignored files mounted at `/run/secrets`, not in Git or the
  display client.

The application can also run directly with Node.js:

```bash
npm ci
npm run build
PORT=8787 DATA_DIR=./data npm start
```

The persistent store contains normalized last values and short network history.
It does not accept or retain prompts, responses, repository paths, or
conversation content. See [`docs/security.md`](docs/security.md) and
[`docs/agent-push-api.md`](docs/agent-push-api.md).

## Development

```bash
npm ci
npm test
npm run build
npm start
```

The frontend uses React and Vite. The production service runs on Node.js and
uses SNMPv3 64-bit counters for the preferred UniFi collection path.

## License

MIT
