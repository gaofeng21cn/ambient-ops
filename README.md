# Ambient Ops

A small self-hosted status aggregator and ambient dashboard for local networks.
It accepts privacy-preserving metrics pushed by machines, polls a UniFi gateway,
and serves display templates for browser kiosks, desktops, tablets, and e-ink
devices.

The display device contains no credentials or business logic. It only opens a
fixed URL served by the aggregator.

## Architecture

```text
machine agents ---- metric snapshots ---+
                                         |
UniFi gateway ---- read-only polling ----+--> Ambient Ops --> browsers
                                         |        (one container)
persistent volume <--- last values ------+
```

The current prototype provides:

- `GET /display/overview` - responsive kiosk overview
- `GET /display/network` - detailed network view
- `GET /display/machines` - per-machine metrics and freshness
- `GET /display/eink` - low-motion, high-contrast e-ink template
- `GET /api/status` - normalized dashboard state
- `POST /api/v1/agents/:machineId/snapshot` - authenticated agent ingestion
- `GET /healthz` - container health check

## Quick Start

```bash
cp .env.example .env
# Set a long random AGENT_PUSH_TOKEN before enabling real agent pushes.
docker compose up --build -d
```

Open `http://<server-address>:8787/display/overview`.

`DEMO_MODE=true` produces clearly marked demonstration data without contacting
external systems. For live operation, set `DEMO_MODE=false`, configure the
UniFi variables, and restart the container.

For a Synology deployment, UniFi API key creation, strict TLS options, and the
optional Home Assistant bridge, see:

- [`docs/deployment-synology.md`](docs/deployment-synology.md)
- [`docs/unifi.md`](docs/unifi.md)
- [`docs/home-assistant.md`](docs/home-assistant.md)

## Deployment Model

The recommended production host is an always-on NAS or small server. The same
application can also run directly with Node.js:

```bash
npm install
npm run build
PORT=8787 DATA_DIR=./data npm start
```

The container persists only normalized metrics and short network history in the
mounted `data/` directory. It does not accept or retain conversation content.

## Private Configuration

Do not commit `.env`, `data/`, credentials, certificates, screenshots, or logs.
The tracked `.env.example` contains placeholders only. See
[`docs/security.md`](docs/security.md) for the trust boundary and
[`docs/agent-push-api.md`](docs/agent-push-api.md) for the ingestion contract.

## Development

```bash
npm install
npm test
npm run build
npm start
```

The frontend uses React and Vite. The production server uses only Node.js core
modules, keeping the runtime container small and easy to audit.

## License

MIT
