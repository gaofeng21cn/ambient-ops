# Ambient Ops

Ambient Ops is a self-hosted status aggregator and five-inch ambient dashboard
for a trusted local network. It combines aggregate Codex activity pushed by
each Mac with read-only WAN counters from a compatible SNMPv3 router, then
serves the normalized state to browsers and the dedicated Android kiosk.

The display has no collection credentials or business logic. It discovers and
opens the one canonical Ambient Ops instance on the LAN.

## Architecture

```text
Codex TPS apps -- authenticated aggregate snapshots --+
                                                       |
SNMPv3 router ---- IF-MIB Counter64 polling -----------+--> Ambient Ops
                                                       |    Node server + React UI
/data ---------- normalized state and short history ---+          |
                                                                  +--> Android kiosk
                                                                  +--> browsers
                                                                  +--> Home Assistant
                                                                       (optional)
```

The server, API, SNMP collector, mDNS publisher, and built frontend ship as one
container. Codex TPS remains a per-Mac agent because raw Codex session files
never leave their host. The Android kiosk is a separate native client.

Available surfaces:

- `GET /display/overview` - five-inch overview
- `GET /display/network` - smoothed 4 Hz WAN chart and current rates
- `GET /display/machines` - per-machine Codex metrics and freshness
- `GET /display/pet` - selected host pet, token rates, and sessions
- `GET /display/eink` - low-motion, high-contrast e-ink view
- `GET /api/status` - normalized dashboard state
- `GET /metrics` - Prometheus text exposition
- `POST /api/v1/agents/:machineId/snapshot` - authenticated ingestion
- `GET /healthz` - process and source status

## Compatibility boundary

The SNMP collector is based on standard IF-MIB, not on a private UniFi MIB.
The `UNIFI_SNMP_*` variable names and `unifi-snmp-v3` source label are
historical. A non-UniFi router can work only when all of these are true:

- SNMPv3 USM `authPriv` is available over IPv4/UDP.
- The configured SHA/AES credentials and read-only view are accepted.
- IF-MIB `ifXTable` is readable at `1.3.6.1.2.1.31.1.1`.
- `ifName`, `ifHCInOctets`, and `ifHCOutOctets` are present for the real WAN
  interface and the 64-bit counters increase with actual traffic.
- One exact interface index, name, or alias can be selected. Multi-WAN may
  select multiple distinct uplinks, but stacked VLAN/PPPoE layers carrying the
  same bytes must not both be selected.
- Hardware/software flow offload does not bypass the exported counters.

SNMP v1/v2c, SNMPv3 without privacy, IPv6-only SNMP endpoints, 32-bit-only
interface counters, proprietary MIBs, and router APIs such as OpenWrt `ubus`
are not supported by the current collector. Do not assume that enabling an
SNMP checkbox makes a router compatible. Qualify its counters first using
[`docs/unifi.md`](docs/unifi.md), which also contains a gated OpenWrt example.

UniFi Network API polling remains an optional fallback for UniFi hardware. An
API key is not required when the preferred SNMPv3 path is live.

## Demo in five minutes

Requirements: Docker Engine/Desktop, Docker Compose v2, `curl`, and `openssl`.

```bash
git clone https://github.com/gaofeng21cn/ambient-ops.git
cd ambient-ops
cp .env.example .env
mkdir -p secrets
umask 077
openssl rand -hex 32 > secrets/agent_push_token
docker compose up --build -d
curl -fsS http://127.0.0.1:8787/healthz
```

Open `http://127.0.0.1:8787/display/overview`. The example defaults to
`DEMO_MODE=true` and discovery disabled, so it cannot silently compete with a
production instance. Stop it with `docker compose down`.

## Complete production installation

This path is reproducible on a Linux Docker host or Synology NAS. A private
repository checkout requires GitHub access. Pin a reviewed tag or commit rather
than deploying a moving branch.

### 1. Prepare the host

Install or provide:

- Git
- Docker Engine and Docker Compose v2
- `curl`, `jq`, and `openssl`
- TCP/8787 from trusted clients to the host
- UDP/5353 multicast on the display/client LAN for mDNS
- UDP/161 from the Ambient Ops host to the router

Clone and pin the source:

```bash
git clone https://github.com/gaofeng21cn/ambient-ops.git
cd ambient-ops
git fetch --tags origin
git switch --detach <reviewed-tag-or-commit>
git rev-parse HEAD
```

Synology must use a Container Manager/Compose version that accepts the
`!reset` tag in `compose.host-network.yaml`. From the pinned checkout, treat
this command as a gate:

```bash
docker compose -f compose.yaml -f compose.host-network.yaml config --quiet
```

If it fails, update Container Manager/Compose before deployment. Do not hand
edit away host networking: the service may run, but Codex TPS and the Android
kiosk will not receive the intended physical-LAN mDNS announcement.

Run the isolated Docker gate on the development/build host. It builds a
production image, pushes a synthetic agent snapshot, checks the pet asset and
read-only root filesystem, restarts the container, and verifies `/data`
persistence. The NAS still needs its own staging checks below:

```bash
./ops/docker/smoke-test.sh
```

### 2. Qualify SNMPv3 and select interfaces

Before creating the production container, verify the router from the future
Docker host or another machine on the same path. The exact commands and OIDs
are in [`docs/unifi.md`](docs/unifi.md). At minimum, two successive reads must
show working 64-bit counters for the intended WAN interface.

Common selectors are an IF-MIB index such as `23`, an `ifName` such as `eth7`
or `pppoe-wan`, or an `ifAlias` such as `WAN`. Names are usually preferable to
indexes when they remain stable after a router reboot. Never copy selectors
from another installation.

Generate known traffic and verify direction:

- WAN `ifHCInOctets` should increase with Internet download.
- WAN `ifHCOutOctets` should increase with Internet upload.
- A tunnel/VLAN/physical stack must be counted once, not once per layer.

If Counter64 is absent, remains zero, decreases outside a reboot, or ignores
offloaded traffic, the router is not compatible with the current collector.

### 3. Create the stable configuration

```bash
cp .env.example .env
mkdir -p secrets
chmod 700 secrets
umask 077
openssl rand -hex 32 > secrets/agent_push_token
touch secrets/unifi_snmp_auth_password secrets/unifi_snmp_priv_password
chmod 600 secrets/*
```

Edit both SNMP password files with a private editor. Each contains only the
corresponding password; a trailing newline is accepted. If the router uses the
same auth and privacy password, enter the same value in both files.

The image runs as the official Node `node` user (UID/GID 1000). On native Linux
and Synology, make that user the owner after writing the files so mode 600 is
both private and readable inside the bind mount:

```bash
sudo chown -R 1000:1000 secrets
sudo chmod 700 secrets
sudo chmod 600 secrets/*
```

Docker Desktop performs its own file-sharing translation and normally does not
need this ownership change. A missing token or SNMP password inside the
container usually means bind ownership/permissions are wrong, not that the
secret should be made world-readable.

Edit `.env` with installation-specific values. This is a complete minimal live
example; replace every angle-bracket placeholder:

```dotenv
AMBIENT_OPS_PORT=8787
DEMO_MODE=false
SITE_NAME=Home Ambient Ops
DISPLAY_TIME_ZONE=Asia/Shanghai

# The base file stays discovery-off for staging. The host override enables it.
DISCOVERY_ENABLED=false
# Stable logical identity: lowercase letters, digits, dot, underscore, hyphen.
INSTANCE_ID=home-ambient-ops

# Historical UNIFI_ prefix; any qualified IF-MIB SNMPv3 router may work.
UNIFI_SNMP_HOST=<router-ipv4-address>
UNIFI_SNMP_PORT=161
UNIFI_SNMP_USER=<snmp-v3-user>
UNIFI_SNMP_AUTH_PROTOCOL=sha
UNIFI_SNMP_PRIV_PROTOCOL=aes
UNIFI_SNMP_INTERFACES=<exact-wan-name-index-or-alias>
UNIFI_SNMP_TIMEOUT_MS=3000
UNIFI_POLL_MS=250
UNIFI_RATE_WINDOW_MS=2000

# Leave the UniFi API fallback empty when SNMPv3 is used.
UNIFI_BASE_URL=
UNIFI_SITE=default
UNIFI_ALLOW_SELF_SIGNED=false
UNIFI_CA_FILE=

LIVE_AFTER_SECONDS=30
STALE_AFTER_SECONDS=300

# Optional and not required for production readiness.
HA_ENABLED=false
HA_BASE_URL=
HA_ENTITY_PREFIX=ambient_ops
HA_SYNC_MS=30000
HA_TIMEOUT_MS=5000
```

`INSTANCE_ID` identifies the logical installation, not its current host or IP.
Never regenerate it during an upgrade or host migration. Back up `.env`, the
`secrets` directory, and the Android signing key outside the repository.

The agent token in `secrets/agent_push_token` must be the exact value stored in
every Codex TPS Mac Keychain. Rotating it is allowed only when every agent is
updated deliberately.

### 4. Stage without announcing the service

The base Compose file publishes TCP/8787 but keeps discovery off:

```bash
docker compose -p ambient-ops -f compose.yaml config --quiet
docker compose -p ambient-ops -f compose.yaml up --build -d
docker compose -p ambient-ops -f compose.yaml ps
```

Require live SNMP before moving clients:

```bash
curl -fsS http://127.0.0.1:8787/healthz |
  jq -e '.ok == true and .mode == "live" and .network == "live"'

curl -fsS http://127.0.0.1:8787/api/status |
  jq -e '.demo == false
    and .network.status == "live"
    and .network.source == "unifi-snmp-v3"
    and (.network.interfaces | length) > 0'
```

At this point Codex may still be `error` because agents have not discovered the
new instance. `healthz.ok=true` alone proves only that the process answers; it
does not prove source readiness.

### 5. Start the one LAN owner

If another Ambient Ops instance is active, stop it first. There must be exactly
one discovery and ingestion owner for a site.

```bash
docker compose -p ambient-ops -f compose.yaml down
docker compose -p ambient-ops \
  -f compose.yaml \
  -f compose.host-network.yaml \
  up --build -d
```

Do not add `-v` to `down`; the named `ambient_ops_data` volume contains the
normalized machine state and short network history. On Synology, also permit
TCP/8787 and LAN mDNS multicast in DSM/firewall policy. See
[`docs/deployment-synology.md`](docs/deployment-synology.md).

### 6. Connect each Codex TPS host

Use Codex TPS `v0.2.5` or newer. Version `v0.2.5` is the first public release
that includes the macOS Ambient Ops settings, automatic
`_ambient-ops._tcp.local` discovery, host pet reporting, and the standard
Windows installer. Older releases do not satisfy this guide. Download only
from the [`releases`](https://github.com/gaofeng21cn/codex-tps/releases) page
and verify the sibling SHA-256 file.

#### macOS

Store the exact server agent token in the login Keychain. With `-w` last,
macOS prompts instead of exposing the token in the command line:

```bash
security add-generic-password -U \
  -a "$USER" \
  -s cn.gaofeng.ambient-ops.agent-push \
  -w

security find-generic-password \
  -a "$USER" \
  -s cn.gaofeng.ambient-ops.agent-push >/dev/null
```

If macOS asks whether Codex TPS may read the item, approve the installed signed
app. In Codex TPS:

1. Expand **Ambient Ops**.
2. Enable **Send aggregate metrics** and **Auto-discover**.
3. Optionally select the pet for this Mac.
4. Require the status to become connected and confirm the displayed endpoint
   is the production host.

Discovery uses `_ambient-ops._tcp.local` and remembers `INSTANCE_ID`. It needs
the Mac and server on an mDNS-reachable LAN; routed VLANs require a correctly
configured mDNS reflector. Client isolation blocks discovery. A manual HTTP(S)
URL is a recovery path, not the preferred permanent setup.

The optional headless agent also discovers automatically when
`CODEX_TPS_AMBIENT_URL` is absent. See the linked Codex TPS README for its
service installation and `CODEX_TPS_AMBIENT_INSTANCE_ID` preference.

#### Windows 11

Download `Codex-TPS-Windows-win-x64-Setup.exe` and its `.sha256` file from the
latest Codex TPS Release. Verify and open the current-user installer:

```powershell
$installer = ".\Codex-TPS-Windows-win-x64-Setup.exe"
$expected = ((Get-Content "$installer.sha256" -Raw).Trim() -split "\s+")[0]
$actual = (Get-FileHash -Algorithm SHA256 $installer).Hash
if ($expected -ne $actual) { throw "Installer checksum mismatch" }
Start-Process $installer -Wait
```

The installer writes the app under `%LOCALAPPDATA%\Programs\Codex TPS` and
registers a standard uninstaller. In **Settings**:

1. Leave the Codex home empty for `%USERPROFILE%\.codex`, or select an explicit
   native/WSL UNC Codex home.
2. Enable **Ambient Ops** and **Auto-discover**.
3. Paste the exact `agent_push_token` value used by this Ambient Ops server.
4. Optionally enable the pet and **Start with Windows**.
5. Accept local-network firewall access for private networks and require the
   Ambient Ops state to become connected.

The Windows installer is not yet Authenticode-signed and can show an
unknown-publisher warning. The published checksum proves byte integrity but
does not replace Windows publisher trust or SmartScreen reputation.

### 7. Build and install the Android kiosk

Requirements for a local build are JDK 17, Android SDK 35, and `adb`. A debug
APK is sufficient for a bounded test:

```bash
brew install openjdk@17
brew install --cask android-commandlinetools android-platform-tools
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
sdkmanager --licenses
sdkmanager "platforms;android-35" "build-tools;35.0.0"

cd android-kiosk
./gradlew :app:testDebugUnitTest :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell cmd package set-home-activity \
  cn.gaofeng.ambientops.kiosk/.MainActivity
adb shell am start -n cn.gaofeng.ambientops.kiosk/.MainActivity
cd ..
```

Production requires one stable signing key. For a fresh production installation
with no previously signed kiosk, create the key and Keychain item below. If a
signed kiosk already exists, skip the `keytool` and `security` commands and use
its existing keystore and Keychain password. The repository helper then builds
the signed release without printing the password:

```bash
mkdir -p "$HOME/Library/Application Support/Ambient Ops/android-signing"
keytool -genkeypair \
  -keystore "$HOME/Library/Application Support/Ambient Ops/android-signing/ambient-ops-release.p12" \
  -storetype PKCS12 \
  -alias ambient-ops \
  -keyalg RSA \
  -keysize 3072 \
  -validity 10000 \
  -dname "CN=Ambient Ops Android"

security add-generic-password -U \
  -a "$USER" \
  -s cn.gaofeng.ambient-ops.android-signing \
  -w

./android-kiosk/scripts/build-signed-release-macos.sh
adb install -r android-kiosk/app/build/outputs/apk/release/app-release.apk
```

Enter the exact PKCS12 password at the Keychain prompt; the helper uses it for
both the store and the `ambient-ops` key alias. Back up the keystore and
password together in an encrypted owner store before installation. Losing
either one prevents in-place updates.

If the bounded debug build from the previous step is installed, Android will
reject the first production APK because the signatures differ. Record any
rescue URL/instance ID, then perform the one-time replacement and restore Home:

```bash
adb uninstall cn.gaofeng.ambientops.kiosk
adb install android-kiosk/app/build/outputs/apk/release/app-release.apk
adb shell cmd package set-home-activity \
  cn.gaofeng.ambientops.kiosk/.MainActivity
```

This one-time uninstall clears kiosk preferences. Every later production
update must use `adb install -r` with the same key.

Do not uninstall a production-signed kiosk before an update: uninstalling
removes its remembered instance, and a different signing key cannot update the
existing app. The one-time debug-to-production transition and signing setup are
documented in [`android-kiosk/README.md`](android-kiosk/README.md).

USB and `adb reverse` are not part of normal operation. After installation the
kiosk is the Android Home activity, discovers the server by Wi-Fi mDNS, keeps
the screen awake, restores immersive mode, and retries after network changes.

### 8. Final acceptance

After Codex TPS has pushed at least once:

```bash
curl -fsS http://<server-ip>:8787/healthz |
  jq -e '.ok == true
    and .mode == "live"
    and .status == "live"
    and .network == "live"
    and .codex == "live"
    and .machines >= 1'

curl -fsS http://<server-ip>:8787/api/status |
  jq -e '.demo == false
    and .overallStatus == "live"
    and .network.source == "unifi-snmp-v3"
    and any(.machines[]; .status == "live")'
```

Also require:

- only one `_ambient-ops._tcp.local` service for this logical installation
- one entry per expected Codex machine, with no legacy duplicate sender
- changing WAN and Codex values on Overview, Network, Machines, and Pet
- `adb reverse --list` empty when USB is attached for diagnostics
- the kiosk returns as Home after an HTC cold reboot without USB
- the container and live state return after a Docker-host/NAS reboot

On a Mac client, browse and resolve the advertised service:

```bash
dns-sd -B _ambient-ops._tcp local.
dns-sd -L "Home Ambient Ops" _ambient-ops._tcp local.
```

Stop each command after the expected result. The resolved TXT record must
contain the configured `id=home-ambient-ops` (or the installation's chosen ID)
and the endpoint must be the production host. On Linux with Avahi, the
equivalent inspection is `avahi-browse -rt _ambient-ops._tcp`.

When the HTC is attached for diagnostics:

```bash
adb reverse --list
adb shell cmd package resolve-activity --brief \
  -a android.intent.action.MAIN -c android.intent.category.HOME
```

The reverse list must be empty and Home must resolve to
`cn.gaofeng.ambientops.kiosk/.MainActivity`.

For a Mac-to-Synology move, follow the stronger owner cutover and rollback gate
in [`docs/production-migration-checklist.md`](docs/production-migration-checklist.md).

## Troubleshooting

Start with:

```bash
docker compose -p ambient-ops \
  -f compose.yaml \
  -f compose.host-network.yaml \
  ps
docker compose -p ambient-ops \
  -f compose.yaml \
  -f compose.host-network.yaml \
  logs --tail=200 ambient-ops
curl -fsS http://<server-ip>:8787/healthz | jq
curl -fsS http://<server-ip>:8787/api/status | jq
```

| Symptom | Check |
| --- | --- |
| Docker says healthy but overall status is error | Read the separate `network` and `codex` fields; the Docker health check proves only HTTP liveness. |
| Network is error | Verify IPv4/UDP 161, authPriv credentials, IF-MIB view, and exact interface selectors. |
| Network stays near zero | Generate known traffic; check Counter64 updates, flow offload, and whether a tunnel/VLAN/physical path was selected correctly. |
| Codex is error or stale | Verify the same token exists in server secrets and Mac Keychain, the integration is enabled, and system time is correct. |
| Codex TPS cannot discover | Verify host networking, UDP/5353, same multicast domain or reflector, Local Network permission, and one canonical publisher. |
| Duplicate Mac appears | Disable the legacy standalone push LaunchAgent, keep one sender, and wait `STALE_AFTER_SECONDS` for retirement. |
| Android shows discovery/retry | Verify Wi-Fi, mDNS reachability, `INSTANCE_ID`, TCP/8787, and that no stale manual URL or reverse tunnel masks the LAN path. |
| Compose rejects `!reset` | Upgrade Docker Compose/Container Manager; do not deploy the host override until `compose config --quiet` passes. |

## Upgrade and rollback

Record the exact current source before changing it:

```bash
AMBIENT_OPS_PREVIOUS_COMMIT=$(git rev-parse HEAD)
git fetch --tags origin
git switch --detach <reviewed-new-tag-or-commit>
./ops/docker/smoke-test.sh
docker compose -p ambient-ops \
  -f compose.yaml \
  -f compose.host-network.yaml \
  up --build -d
```

Record `AMBIENT_OPS_PREVIOUS_COMMIT` outside the shell before proceeding.

Repeat the final acceptance. Keep `.env`, `secrets`, `INSTANCE_ID`, the agent
token, and the named volume unchanged.

To roll back the server code, rebuild the recorded commit against the same
configuration and volume:

```bash
git switch --detach "$AMBIENT_OPS_PREVIOUS_COMMIT"
docker compose -p ambient-ops \
  -f compose.yaml \
  -f compose.host-network.yaml \
  up --build -d
```

Never use `docker compose down -v` for an upgrade or rollback. Android upgrades
must retain the same application ID and signing key and increase `versionCode`.
A host migration has stricter single-owner ordering; use the production
migration checklist rather than running old and new instances together.

## Development and direct Node operation

```bash
npm ci
npm test
npm run build
PORT=8787 DATA_DIR=./data npm start
```

The persistent store contains normalized last values and short network history.
It does not accept or retain prompts, responses, repository paths, or
conversation content. See:

- [`docs/security.md`](docs/security.md)
- [`docs/agent-push-api.md`](docs/agent-push-api.md)
- [`docs/unifi.md`](docs/unifi.md)
- [`docs/deployment-synology.md`](docs/deployment-synology.md)
- [`docs/home-assistant.md`](docs/home-assistant.md)

## License

MIT
