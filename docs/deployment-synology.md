# Synology Deployment

Ambient Ops runs as one Linux container. The NAS owns aggregation, persistence,
LAN discovery, and the web app; display clients only discover and open it.

Use [`production-migration-checklist.md`](production-migration-checklist.md) for
an existing Mac-to-NAS cutover. This page describes the target installation.
For the shorter ordinary-user path, start with the
[installation guide](installation.md) or its
[Chinese edition](installation.zh-CN.md).

## Requirements

- Synology Container Manager or Docker Compose over SSH
- A persistent project directory, for example
  `/volume1/docker/ambient-ops`
- UDP/161 access from the NAS to the qualified SNMPv3 router
- TCP/8787 access from trusted LAN clients to the NAS
- UDP/5353 multicast on the client LAN
- Host networking for Bonjour/mDNS publication to the physical LAN
- A Compose implementation that accepts the `!reset` tag used by the
  host-network override

Tagged releases publish one GHCR manifest containing both `linux/amd64` and
`linux/arm64` images. Intel and ARM Synology models pull the native image; the
NAS does not build Node or frontend assets locally.

Check the exact Compose merge before copying any secrets:

```bash
docker compose -f compose.yaml -f compose.host-network.yaml config --quiet
```

If Synology Container Manager rejects `!reset`, update it or install a
compatible Compose v2 CLI. A base-only container can serve HTTP but cannot
prove physical-LAN mDNS discovery.

The commands below use the Compose CLI over Synology SSH because this preserves
the repository's two-file merge exactly. Container Manager may still be used to
observe and restart the resulting container. If a DSM UI release supports the
same multi-file project definition, compare its rendered configuration with
the CLI output before treating it as equivalent.

## Prepare configuration

Clone or copy a reviewed source commit into the persistent project directory:

```bash
cd /volume1/docker/ambient-ops
./scripts/ambient-ops.sh init
```

The helper refuses to overwrite an existing installation, generates a stable
`INSTANCE_ID` and agent token without printing them, and creates the optional
secret files. Edit only `.env`; enter SNMPv3 passwords with the documented
interactive `set-secret` commands. A manual `cp .env.example .env` path remains
valid for operators who deliberately manage identity and secret generation
themselves.

Set `AMBIENT_OPS_IMAGE` in `.env` to the reviewed release, for example
`ghcr.io/gaofeng21cn/ambient-ops:0.1.6`. The GitHub Container Registry package
is public, so Synology can pull the image without a GitHub token:

```bash
docker compose -p ambient-ops -f compose.yaml pull
```

Do not add GitHub credentials to `.env`, Compose, or the repository for normal
pulls.

For a fresh installation, generate a new **agent push token** as above. For a
migration, copy the existing agent push token instead; changing it makes every
Codex TPS agent fail with HTTP 401 until its Keychain item is updated.

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

The container runs as UID/GID 1000. After writing every secret, make that user
the bind-directory owner while retaining owner-only modes:

```bash
sudo chown -R 1000:1000 secrets
sudo chmod 700 secrets
sudo chmod 600 secrets/*
```

Do not solve a permission failure with mode 644. Readability must be granted to
the container user without making credentials available to unrelated host
users.

`INSTANCE_ID` identifies the logical installation, not the host. Keep it stable
when the service moves to another address or port. The Android kiosk remembers
this ID and can follow its new mDNS endpoint.

Before copying the reviewed commit to production, run the repository-owned
isolated gate on a Docker development/build host:

```bash
./ops/docker/smoke-test.sh
```

## Stage without LAN discovery

The base Compose file publishes TCP/8787 and leaves mDNS disabled. Use it to
build and check the candidate without competing with a running production
instance:

```bash
docker compose -p ambient-ops -f compose.yaml pull
docker compose -p ambient-ops -f compose.yaml up -d
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
  pull
docker compose -p ambient-ops \
  -f compose.yaml \
  -f compose.host-network.yaml \
  up -d
```

The named `ambient_ops_data` volume is preserved by `down`; never add `-v`
during an upgrade. The volume retains normalized machine snapshots, network
state, and short history across container replacement.

Host networking removes the published-port mapping and publishes
`_ambient-ops._tcp.local` directly to the LAN. The Compose service listens on
TCP/8787 in this mode. Allow TCP/8787 and LAN mDNS in DSM Firewall without
exposing them to WAN interfaces.

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

Codex TPS needs the exact `secrets/agent_push_token` value in each host's
credential store: Keychain service `cn.gaofeng.ambient-ops.agent-push` on macOS
or DPAPI-backed settings on Windows. Enable aggregate sending and auto-discovery
in the app. The Android kiosk must load through Wi-Fi discovery with
`adb reverse --list` empty. The root [`README`](../README.md) contains the
complete agent and APK installation commands.

## Upgrade and rollback

Pin and record source commits. Qualify the new commit with
`./ops/docker/smoke-test.sh`, then recreate the service with both Compose files:

```bash
docker compose -p ambient-ops \
  -f compose.yaml \
  -f compose.host-network.yaml \
  pull
docker compose -p ambient-ops \
  -f compose.yaml \
  -f compose.host-network.yaml \
  up -d
```

Repeat live network/Codex, mDNS, HTC, and reboot readbacks. To roll back, set
`AMBIENT_OPS_IMAGE` to the recorded prior release and run the same commands. Keep
`.env`, `secrets`, `INSTANCE_ID`, and the named volume unchanged. Never use
`down -v` during an upgrade or rollback.

Inspect failures with:

```bash
docker compose -p ambient-ops \
  -f compose.yaml \
  -f compose.host-network.yaml \
  logs --tail=200 ambient-ops
curl -fsS http://127.0.0.1:8787/healthz
curl -fsS http://127.0.0.1:8787/api/status
```

If DSM reports **Unable to build project ambient-ops**, treat that as a project
definition error. Production uses the public versioned image and must not
build. Confirm that the project uses `compose.yaml` plus
`compose.host-network.yaml`, does not include `compose.local-build.yaml`, and
renders no `build:` key. A GHCR login or DSM scheduled task is not a fix: the
package is public and `restart: unless-stopped` owns normal container startup.

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
