# Synology Deployment

Ambient Ops runs as one Linux container. The NAS owns aggregation, persistence,
LAN discovery, and the web app; display clients only discover and open it.

Use [`production-migration-checklist.md`](production-migration-checklist.md) for
an existing Mac-to-NAS cutover. This page describes the target installation.

## Requirements

- Synology Container Manager or Docker Compose over SSH
- A persistent project directory, for example
  `/volume1/docker/ambient-ops`
- UDP/161 access from the NAS to the UniFi gateway
- TCP/8787 access from trusted LAN clients to the NAS
- Host networking for Bonjour/mDNS publication to the physical LAN

The Dockerfile uses the multi-platform official `node:22-alpine` base. Building
on the NAS selects the native architecture. Registry releases for both Intel
and ARM Synology models must use a multi-platform manifest.

## Prepare configuration

Clone or copy a reviewed source commit into the persistent project directory:

```bash
cd /volume1/docker/ambient-ops
cp .env.example .env
mkdir -p secrets
chmod 700 secrets
umask 077
openssl rand -hex 32 > secrets/agent_push_token
```

Set at least:

```dotenv
DEMO_MODE=false
SITE_NAME=Ambient Ops
DISPLAY_TIME_ZONE=Asia/Shanghai
INSTANCE_ID=<stable-existing-or-new-id>
UNIFI_SNMP_HOST=<gateway-address>
UNIFI_SNMP_USER=<snmp-v3-user>
UNIFI_SNMP_INTERFACES=<wan-interface-or-index>,<second-wan-if-used>
UNIFI_POLL_MS=250
UNIFI_RATE_WINDOW_MS=2000
```

Write SNMPv3 credentials to:

```text
secrets/unifi_snmp_auth_password
secrets/unifi_snmp_priv_password
```

If the same password is configured for authentication and privacy, both files
may contain the same value. The application trims surrounding whitespace when
reading secret files.

`INSTANCE_ID` identifies the logical installation, not the host. Keep it stable
when the service moves to another address or port. The Android kiosk remembers
this ID and can follow its new mDNS endpoint.

## Stage without LAN discovery

The base Compose file publishes TCP/8787 and leaves mDNS disabled. Use it to
build and check the candidate without competing with a running production
instance:

```bash
docker compose -p ambient-ops -f compose.yaml up --build -d
docker compose -p ambient-ops -f compose.yaml ps
curl -fsS http://127.0.0.1:8787/healthz
curl -fsS http://127.0.0.1:8787/api/status
```

For a live SNMP configuration, require `mode=live`, `network=live`, and
`network.source=unifi-snmp-v3`. Codex may remain error during staging because
the agents must still target the canonical production instance.

Do not infer source readiness from HTTP 200 or `ok=true` alone. `/healthz`
separately reports the normalized source state.

## Start the LAN instance

Linux/Synology production needs the host-network override:

```bash
docker compose -p ambient-ops -f compose.yaml down
docker compose -p ambient-ops \
  -f compose.yaml \
  -f compose.host-network.yaml \
  up --build -d
```

The named `ambient_ops_data` volume is preserved by `down`; never add `-v`
during an upgrade. The volume retains normalized machine snapshots, network
state, and short history across container replacement.

Host networking removes the published-port mapping and publishes
`_ambient-ops._tcp.local` directly to the LAN. The Compose service listens on
TCP/8787 in this mode.

## Validate persistence

Run the persistence probe while the service is still being qualified:

```bash
docker compose -p ambient-ops \
  -f compose.yaml \
  -f compose.host-network.yaml \
  exec ambient-ops sh -c 'printf persisted > /data/.persistence-probe'

docker compose -p ambient-ops \
  -f compose.yaml \
  -f compose.host-network.yaml \
  up -d --force-recreate

docker compose -p ambient-ops \
  -f compose.yaml \
  -f compose.host-network.yaml \
  exec ambient-ops test -f /data/.persistence-probe

docker compose -p ambient-ops \
  -f compose.yaml \
  -f compose.host-network.yaml \
  exec ambient-ops rm /data/.persistence-probe
```

After the acceptance checks pass, reboot the NAS once and repeat the health,
API, discovery, HTC, and Codex TPS readbacks. `restart: unless-stopped` is not
proof until the service has returned after a real daemon/host restart.

## URLs

- `http://<nas-address>:8787/display/overview`
- `http://<nas-address>:8787/display/network`
- `http://<nas-address>:8787/display/machines`
- `http://<nas-address>:8787/display/pet`
- `http://<nas-address>:8787/display/eink`
- `http://<nas-address>:8787/api/status`
- `http://<nas-address>:8787/healthz`

The display endpoints and `/api/status` intentionally have no browser
authentication. Restrict them to the trusted LAN or a private VPN. See
[`security.md`](security.md).
