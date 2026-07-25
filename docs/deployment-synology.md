# Synology Deployment

Ambient Ops runs as one Linux container. The NAS performs aggregation and
serves the web app; the display device only opens a URL.

## Prepare the project

1. Copy or clone the repository into a persistent NAS folder, for example
   `/volume1/docker/ambient-ops`.
2. Copy `.env.example` to `.env` in that folder.
3. Create `secrets/agent_push_token` containing a long random push token.
4. Put SNMPv3 credentials in `secrets/unifi_snmp_auth_password` and
   `secrets/unifi_snmp_priv_password`.
5. Keep `.env`, `secrets/`, certificates, and Compose overrides outside Git.

Example token generation:

```bash
mkdir -p secrets
umask 077
openssl rand -hex 32 > secrets/agent_push_token
```

## Start with Container Manager

In Synology Container Manager, create a Project from the repository's
`compose.yaml`, select the folder containing `.env`, then build and start it.
The equivalent SSH command is:

```bash
cd /volume1/docker/ambient-ops
docker compose -f compose.yaml -f compose.host-network.yaml up --build -d
docker compose ps
curl http://127.0.0.1:8787/healthz
```

Open these LAN URLs after the health check succeeds:

- `http://<nas-address>:8787/display/overview`
- `http://<nas-address>:8787/display/network`
- `http://<nas-address>:8787/display/machines`
- `http://<nas-address>:8787/display/eink`

## Move from demo to live data

Set `DEMO_MODE=false`, configure the non-secret UniFi variables described in
[`unifi.md`](unifi.md), and restart the project. Configure machine agents with
the NAS URL and the token stored in `secrets/agent_push_token`.

The named volume `ambient_ops_data` retains normalized last values, the stable
discovery instance ID, and WAN history across container replacement. Back up
this volume only if retaining short status history matters; it contains no
prompt or response content.

`compose.host-network.yaml` is required on Linux/Synology so Bonjour/mDNS
announcements reach the physical LAN. The base Compose file uses a published
TCP port and disables discovery, which is suitable for Docker Desktop testing.

## Platform compatibility

The Dockerfile uses the multi-platform official `node:22-alpine` base image.
Building on the NAS selects its native architecture. A registry image intended
for both Intel and ARM Synology models should be published as a multi-platform
manifest rather than copied from a single-architecture local build.
