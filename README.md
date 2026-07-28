<p align="center">
  <strong>English</strong> | <a href="./README.zh-CN.md">中文</a>
</p>

<h1 align="center">Ambient Ops</h1>

<p align="center"><strong>A quiet, always-on, self-hosted view of operational state across your local network</strong></p>
<p align="center">Codex TPS aggregates · Router telemetry · Browser and Android displays</p>

<p align="center">
  <a href="https://github.com/gaofeng21cn/ambient-ops/releases/latest"><img src="https://img.shields.io/github/v/release/gaofeng21cn/ambient-ops" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/deployment-Docker-blue.svg" alt="Docker deployment">
</p>

<table>
  <tr>
    <td width="33%" valign="top">
      <strong>Primary Use</strong><br/>
      See Codex activity, network throughput, device freshness, and pet state in one trusted-LAN dashboard
    </td>
    <td width="33%" valign="top">
      <strong>Interfaces</strong><br/>
      Browsers, a five-inch Android kiosk, Prometheus, and optional Home Assistant synchronization
    </td>
    <td width="33%" valign="top">
      <strong>Privacy Boundary</strong><br/>
      Raw Codex sessions remain on each computer; the server accepts only allowlisted aggregate metrics
    </td>
  </tr>
</table>

> Ambient Ops is designed for a trusted local network, not as an internet-facing monitoring service. Display, status, and device-approval pages have no browser login by default. Add HTTPS and access control or use a private VPN before crossing an untrusted network.

## For Users

### What it is

Ambient Ops is a self-hosted status aggregator for a local network. It combines
aggregate Codex activity from multiple computers with optional live WAN counters
from a compatible router, then presents the normalized state through browser and
dedicated Android displays.

It is intentionally narrower than a general observability platform. It helps when
you want to:

- glance at recent Codex activity across several machines;
- keep download, upload, and latency visible on an ambient screen;
- give browsers and a dedicated display one canonical status source; and
- keep the deployment self-hosted without sending conversation content to a third party.

### How Codex TPS fits

[Codex TPS](https://github.com/gaofeng21cn/codex-tps) runs on each macOS or Windows
computer and reads usage events already written by the local Codex client. It sends
only machine identity, platform, collection time, aggregate `1m` and `5m` token
counters, active-session count, and optional pet state.

Session identifiers, local paths, prompts, responses, tool content, and repository
files are never transmitted.

Current desktop clients use one-time device approval. Codex TPS creates a local
per-device key, the user verifies a six-digit pairing code, and subsequent snapshots
are signed. Shared bearer tokens remain only for legacy and headless agents.

### Architecture

```text
Codex TPS on each computer -- authenticated aggregate snapshots --+
                                                                  |
SNMPv3 router -------------- standard IF-MIB counters ------------+--> Ambient Ops
                                                                  |    container
/data ---------------------- state and short history -------------+       |
                                                                         +--> browsers
                                                                         +--> Android kiosk
                                                                         +--> Prometheus
                                                                         +--> Home Assistant
                                                                              (optional)
```

The server, API, SNMP collector, LAN discovery publisher, and frontend ship in one
container. The Android kiosk discovers and displays the canonical instance; it does
not contain collection credentials or aggregation logic.

### What you get

- Overview, Network, Machines, single-machine Load, Pet, and e-ink display surfaces
- Aggregate Codex throughput, active-session, and freshness state across machines
- Standard IF-MIB `Counter64` download/upload metrics and optional latency
- Prometheus text metrics and optional Home Assistant synchronization
- LAN discovery for the dedicated Android kiosk
- Versioned Docker images, health checks, persistent state, and rollbackable upgrades

### Quick start

Requirements: Docker Engine, Docker Compose v2, `curl`, and `openssl`.

```bash
git clone https://github.com/gaofeng21cn/ambient-ops.git
cd ambient-ops
./scripts/ambient-ops.sh init
```

This creates the minimal `codex-only` configuration. Most users edit only the
site name and time zone in `.env`:

```dotenv
SITE_NAME=Home Ambient Ops
DISPLAY_TIME_ZONE=Asia/Shanghai
```

The template pins a reviewed release image. Change `AMBIENT_OPS_IMAGE` only when
deliberately moving to a newer reviewed
[release](https://github.com/gaofeng21cn/ambient-ops/releases/latest); never use `latest`.

If router telemetry is needed from the beginning, select the profile during
initialization:

```bash
./scripts/ambient-ops.sh init --profile snmpv3
# or: ./scripts/ambient-ops.sh init --profile unifi-api
```

The SNMPv3 profile also requires both passwords through the interactive helpers:

```bash
./scripts/ambient-ops.sh set-secret unifi_snmp_auth_password
./scripts/ambient-ops.sh set-secret unifi_snmp_priv_password
./scripts/ambient-ops.sh validate
./scripts/ambient-ops.sh up
./scripts/ambient-ops.sh status
```

`init` refuses to overwrite an existing configuration. It creates a stable instance
ID and shared agent token without printing secret material. Tokens and passwords live
under the ignored `secrets/` directory and must not be copied into `.env`, commands,
logs, screenshots, or Git.

See the [installation guide](docs/installation.md) for the complete Docker, Synology,
upgrade, rollback, and Android kiosk path.

### Network modes

| Mode | Use case | Additional configuration |
| --- | --- | --- |
| `codex-only` | Codex and pet state only | Created by default with `init`; no router configuration |
| `snmpv3` | Preferred generic router path | `init --profile snmpv3`; router address, read-only user, selectors, and two passwords |
| `unifi-api` | UniFi Network API fallback | `init --profile unifi-api`; controller URL, site, and API-key file |

The SNMP path uses standard IF-MIB rather than a private UniFi MIB. A router must still
support SNMPv3 `authPriv` and expose `ifHCInOctets` and `ifHCOutOctets` for the real WAN
interfaces. “SNMP enabled” is not sufficient; qualify the device with
[`docs/unifi.md`](docs/unifi.md).

### Important boundaries

- Run exactly one Ambient Ops instance that publishes discovery and accepts snapshots for a site.
- Production `compose.yaml` is self-contained and uses host networking so DSM
  Container Manager can load it as a single project file. `compose.host-network.yaml`
  remains a compatibility override for older operator commands; `compose.local-build.yaml`
  is for local development only.
- Do not expose the service directly to the internet.
- Preserve `.env`, `INSTANCE_ID`, `secrets/`, and the `ambient_ops_data` volume during upgrades.
- Do not run `docker compose down -v` unless permanent data deletion is intentional.

## For Agents

### Recommended task prompt

Replace only the non-sensitive placeholders:

```text
Install or upgrade Ambient Ops on <Docker host> under <absolute target directory>.
Use SITE_NAME=<site name>, DISPLAY_TIME_ZONE=<IANA time zone>, and
AMBIENT_OPS_NETWORK_MODE=<codex-only|snmpv3|unifi-api>.

Follow docs/installation.md, docs/agent-installation.md, and
scripts/ambient-ops.sh. Use only a reviewed versioned GHCR image in production.
Do not build source on the NAS, use a moving image tag, create unnecessary GitHub
credentials, or add a scheduler that duplicates the container restart policy.

Do not request, read, print, or copy tokens and passwords. When a secret is needed,
ask me to run the documented interactive set-secret command in a trusted terminal.
An existing installation must preserve .env, INSTANCE_ID, secrets/, and
ambient_ops_data. Never run docker compose down -v.

Before completion, read back the rendered image, /healthz, /api/status, mDNS
discovery, expected machine list, and Android kiosk connection. A successful build,
HTTP 200 response, or running container is not complete acceptance.
```

### Agent installation sequence

For a new installation:

```bash
git clone https://github.com/gaofeng21cn/ambient-ops.git <target>
cd <target>
git rev-parse HEAD
./scripts/ambient-ops.sh init --profile <codex-only|snmpv3|unifi-api>
```

Modify only documented non-secret `.env` fields. The user enters real tokens and
passwords in a trusted terminal.

```bash
./scripts/ambient-ops.sh validate
docker compose --env-file .env -p ambient-ops \
  -f compose.yaml -f compose.host-network.yaml config --images
./scripts/ambient-ops.sh up
./scripts/ambient-ops.sh status
```

Do not run `init` for an existing installation. Before upgrading, record the current
source commit, effective image, health readback, and exact rollback command. Change
`AMBIENT_OPS_IMAGE` only to a reviewed version and repeat validation and acceptance.

### Agent authority and evidence boundaries

- Inspect secret-file existence, ownership, and mode without opening the content.
- Configure router addresses, read-only usernames, and selectors without asking the user to paste passwords into chat.
- Distinguish process health from configured-source readiness.
- Treat device approval, signing identity, and real host restarts as explicit user actions.
- Preserve the single-instance rule during migration: stop the old writer before starting the new LAN authority.

The full contract is in the [Agent installation guide](docs/agent-installation.md).

## Documentation

- [Installation guide](docs/installation.md)
- [Agent installation guide](docs/agent-installation.md)
- [Security and privacy](docs/security.md)
- [Agent push API](docs/agent-push-api.md)
- [Router and SNMPv3](docs/unifi.md)
- [Synology deployment](docs/deployment-synology.md)
- [Android kiosk](docs/macos-htc-kiosk.md)
- [Migration acceptance checklist](docs/production-migration-checklist.md)

## Technical Validation

```bash
npm ci
npm test
npm run build
docker compose -f compose.yaml config
docker compose -f compose.yaml -f compose.host-network.yaml config
python3 ops/public-readiness-check.py
```

Ambient Ops is available under the [MIT License](LICENSE).
