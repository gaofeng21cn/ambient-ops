# Ambient Ops Installation Guide

[简体中文](installation.zh-CN.md) | **English**

This is the ordinary-user path for a Linux Docker host or Synology NAS. It
uses one non-secret `.env` file, private files under `secrets/`, the public
multi-platform image, and the signed Android APK. The NAS never builds the
application from source.

## What you need

- A Linux host or Synology NAS with Docker Engine and Docker Compose v2
- `git`, `curl`, and `openssl` on the Docker host
- TCP/8787 reachable only from the trusted LAN or private VPN
- UDP/5353 multicast between the server, Codex TPS computers, and Android kiosk
- Optional: IPv4/UDP 161 from the Docker host to a qualified SNMPv3 router
- Optional for initial Android installation: a computer with `adb`

The current published server image is
`ghcr.io/gaofeng21cn/ambient-ops:0.1.2` for both `linux/amd64` and
`linux/arm64`. The package is public. Do not create or configure a GitHub token
for a normal pull.

## 1. Create the installation

Choose a persistent directory. On Synology, a typical location is
`/volume1/docker/ambient-ops`.

```bash
git clone https://github.com/gaofeng21cn/ambient-ops.git
cd ambient-ops
git rev-parse HEAD
./scripts/ambient-ops.sh init
```

`init` refuses to overwrite an existing `.env`. It creates:

- `.env` with a stable generated `INSTANCE_ID`
- `secrets/agent_push_token` with a random 256-bit token
- empty optional secret files for SNMPv3, UniFi API, and Home Assistant

No secret is printed. Keep `.env`, `secrets/`, and the Docker volume when
upgrading or moving the service.

## 2. Edit one configuration file

Open `.env` in a local text editor. For a Codex-only screen, these are the only
values most users review:

```dotenv
AMBIENT_OPS_IMAGE=ghcr.io/gaofeng21cn/ambient-ops:0.1.2
AMBIENT_OPS_PORT=8787
SITE_NAME=Home Ambient Ops
DISPLAY_TIME_ZONE=Etc/UTC
INSTANCE_ID=ao-generated-and-stable
DEMO_MODE=false
AMBIENT_OPS_NETWORK_MODE=codex-only
```

Use an IANA time-zone name such as `Asia/Shanghai`, `Europe/London`, or
`America/Los_Angeles`. Preserve `INSTANCE_ID` exactly after the first start.

Choose one network profile:

| Profile | Use it when | Required additions |
| --- | --- | --- |
| `codex-only` | Only Codex and pet pages are required | None |
| `snmpv3` | SNMPv3 router | Address, user, WAN selector, two passwords |
| `unifi-api` | UniFi API fallback | Controller URL and API key file |

### SNMPv3 profile

Set the non-secret values in `.env`:

```dotenv
AMBIENT_OPS_NETWORK_MODE=snmpv3
UNIFI_SNMP_HOST=192.168.1.1
UNIFI_SNMP_USER=ambient-ops
UNIFI_SNMP_INTERFACES=WAN
UNIFI_SNMP_PORT=161
UNIFI_SNMP_AUTH_PROTOCOL=sha
UNIFI_SNMP_PRIV_PROTOCOL=aes
UNIFI_POLL_MS=250
UNIFI_RATE_WINDOW_MS=2000
```

`UNIFI_SNMP_INTERFACES` is an exact case-insensitive IF-MIB index, `ifName`, or
`ifAlias`. Separate distinct WAN uplinks with commas. Do not count VLAN,
PPPoE, tunnel, and physical layers carrying the same traffic more than once.

Enter the two passwords without putting them in shell history:

```bash
./scripts/ambient-ops.sh set-secret unifi_snmp_auth_password
./scripts/ambient-ops.sh set-secret unifi_snmp_priv_password
```

The historical `UNIFI_` prefix does not bind the collector to UniFi. A router
is compatible only after its `ifHCInOctets` and `ifHCOutOctets` counters are
verified under real traffic. Follow [Router and SNMP qualification](unifi.md).

### UniFi API fallback

Set:

```dotenv
AMBIENT_OPS_NETWORK_MODE=unifi-api
UNIFI_BASE_URL=https://192.168.1.1
UNIFI_SITE=default
```

Then run:

```bash
./scripts/ambient-ops.sh set-secret unifi_api_key
```

An API key is not needed when the SNMPv3 profile is live.

## 3. Protect secrets on Linux and Synology

The container runs as UID/GID 1000. After all optional secrets have been
entered, make them private and readable by that non-root user:

```bash
sudo chown -R 1000:1000 secrets
sudo chmod 700 secrets
sudo chmod 600 secrets/*
```

Docker Desktop on macOS normally translates bind-mount ownership and does not
need this step. Do not use mode 644 as a permission workaround.

## 4. Validate and start

```bash
./scripts/ambient-ops.sh validate
./scripts/ambient-ops.sh up
```

The helper validates required fields and secret files, renders the production
Compose merge, pulls the pinned public image, and starts it with
`restart: unless-stopped`. It never selects `compose.local-build.yaml`.

Check at any time:

```bash
./scripts/ambient-ops.sh status
./scripts/ambient-ops.sh logs
curl -fsS http://<server-ip>:8787/api/status
```

`/healthz` returning HTTP 200 proves process liveness. Read its `network`,
`codex`, and `machines` fields separately. In `codex-only` mode, network
readiness is intentionally not an acceptance condition.

## 5. Connect every Codex TPS computer

Install Codex TPS `v0.2.5` or later from its
[Releases page](https://github.com/gaofeng21cn/codex-tps/releases). Each
computer keeps its own raw Codex sessions and sends only aggregate snapshots.

Every computer must use the exact value in `secrets/agent_push_token`. Open the
file locally with a private editor and paste it into Codex TPS; do not paste it
into chat, screenshots, tickets, or documentation.

On macOS, Codex TPS stores the token in the login Keychain service
`cn.gaofeng.ambient-ops.agent-push`. Enable **Send aggregate metrics** and
**Auto-discover**. On Windows, enable Ambient Ops and Auto-discover in Settings;
the native app stores the token with Windows DPAPI.

After each host pushes, require one stable machine entry with a live timestamp.
If the same host appears twice, stop the legacy sender rather than deleting
live state repeatedly.

## 6. Install the Android kiosk

Download these assets from
[Ambient Ops v0.1.2](https://github.com/gaofeng21cn/ambient-ops/releases/tag/v0.1.2):

- `Ambient-Ops-Kiosk-1.1.1.apk`
- `Ambient-Ops-Kiosk-1.1.1.apk.sha256`

Verify and install:

```bash
shasum -a 256 -c Ambient-Ops-Kiosk-1.1.1.apk.sha256
adb install -r Ambient-Ops-Kiosk-1.1.1.apk
adb shell cmd package set-home-activity \
  cn.gaofeng.ambientops.kiosk/.MainActivity
adb shell am start -n cn.gaofeng.ambientops.kiosk/.MainActivity
```

The production APK is owner-signed. Future in-place updates must keep the same
application ID and signing certificate and increase `versionCode`. Install
them with `adb install -r`; do not uninstall the production app first.
The current release has no in-app updater; this verified Release-to-ADB flow is
the supported upgrade path.

Once installed, USB is not part of normal operation. The kiosk uses Wi-Fi mDNS,
remembers the logical instance, stays immersive, and retries after network
changes.

## 7. Accept the installation

Require all applicable checks:

- Compose resolves to a versioned GHCR image and contains no `build:`.
- `/healthz` reports `mode=live`.
- Every expected Codex TPS host appears once and is live.
- With `snmpv3`, `network=live` and WAN rates change under known traffic.
- The Android kiosk loads every page over Wi-Fi with `adb reverse --list` empty.
- The kiosk returns as Android Home after a cold reboot without USB.
- Ambient Ops returns after a real Docker-host or NAS reboot.

`restart: unless-stopped` is the container restart policy. A DSM Task Scheduler
job is neither required nor recommended.

## Upgrade and rollback

Before an upgrade, record the current image and repository commit:

```bash
docker compose --env-file .env -p ambient-ops \
  -f compose.yaml -f compose.host-network.yaml config --images
git rev-parse HEAD
```

Change only `AMBIENT_OPS_IMAGE` to the reviewed new version, update the checked
out deployment files when required by that release, then run:

```bash
./scripts/ambient-ops.sh validate
./scripts/ambient-ops.sh up
```

Repeat the acceptance checks. To roll back, restore the recorded image and
deployment commit and run the same two commands. Keep `.env`, `secrets/`,
`INSTANCE_ID`, and the named `ambient_ops_data` volume. Never use
`docker compose down -v` during upgrade or rollback.

## Synology build-error recovery

Production does not build a project. If DSM reports **Unable to build project
ambient-ops**, inspect Container Manager logs and the project Compose files.
The production merge must use only:

```text
compose.yaml
compose.host-network.yaml
```

It must not include `compose.local-build.yaml`, and rendered Compose must not
contain `build:`. Verify over SSH:

```bash
docker compose --env-file .env -p ambient-ops \
  -f compose.yaml -f compose.host-network.yaml config --quiet
docker compose --env-file .env -p ambient-ops \
  -f compose.yaml -f compose.host-network.yaml config --images
```

The image should be `ghcr.io/gaofeng21cn/ambient-ops:<version>`. It is public,
so GHCR login and DSM scheduled tasks are not needed. See the detailed
[Synology deployment reference](deployment-synology.md) for migration,
persistence, firewall, and reboot checks.

## Current product boundary

This path is designed for self-service by a Docker-capable user or an Agent
working under the companion guide. It still requires local decisions about
LAN/firewall policy, a stable installation identity, and optional router
credentials and WAN selection. Router compatibility is evidence-based, not a
brand-wide guarantee.

Advanced API, security, Home Assistant, migration, local development, and
Android signing material remains documented in the existing repository
references; this quick path does not replace those documents.
