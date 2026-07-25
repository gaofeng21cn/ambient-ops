# Ambient Ops Git Collaboration

Prepared on 2026-07-25 after the user moved the HTC USB connection to the Mac.
Windows is no longer a feature or device-operation writer for this task. This
repository is the canonical source transfer surface for continued work on the
Mac.

## Git Context

- Repository: `https://github.com/gaofeng21cn/ambient-ops`
- Branch: `feat/functional-prototype`
- Visibility: private
- Windows delivery scope: the complete Ambient Ops functional prototype,
  documentation, tests, and container configuration

Clone the repository on the Mac and check out the delivery branch:

```bash
git clone https://github.com/gaofeng21cn/ambient-ops.git
cd ambient-ops
git switch feat/functional-prototype
```

Continue all feature development, HTC device operations, live integration, and
deployment from the Mac checkout. Do not restore the stopped Windows ADB,
scrcpy, development-server, browser-test, or verification-container processes.

## Completed Verification

| Surface | Result |
| --- | --- |
| Node tests | 10/10 passed |
| Vite production build | Passed |
| `npm audit`, production and full tree | 0 vulnerabilities |
| Docker image build | Passed with `node:22-alpine` |
| Container health and API status | Passed in demo mode |
| Compose expansion | Passed with strict TLS default |
| Agent API normalization/privacy tests | Passed |
| Prometheus output | Passed |
| Home Assistant mapping/failure isolation tests | Passed |
| Desktop browser, 1280x720 | Passed |
| Concept-size browser, 1672x941 | Passed |
| Network, Machines, machine selection | Passed |
| Mobile browser, 412x915 | Passed without horizontal overflow |
| E-ink, 1280x720 | Passed, black/white, no animation or overflow |
| Browser console | Zero application errors/warnings after final fixes |
| Concept-to-render `view_image` comparison | Completed |

The Browser plugin failed in the WSL workspace because `sandboxCwd` was not a
local file URI. The rendered validation used Playwright Chromium instead.

## Not Completed

- Latest Ambient Ops build on the physical HTC. Windows lost the USB device and
  the user moved the cable to the Mac before final device validation.
- Live UniFi polling. A dedicated API key is still required.
- Live Home Assistant writeback. A long-lived token is still required.
- Synology production deployment and owner-authoritative health readback.
- `codex-tps` macOS/Windows agent changes and signed Mac distribution.

## Configuration Schema

```text
PORT
DATA_DIR
DEMO_MODE
SITE_NAME
DISPLAY_TIME_ZONE
AGENT_PUSH_TOKEN
UNIFI_BASE_URL
UNIFI_SITE
UNIFI_API_KEY
UNIFI_ALLOW_SELF_SIGNED
UNIFI_CA_FILE
UNIFI_POLL_MS
LIVE_AFTER_SECONDS
STALE_AFTER_SECONDS
HA_ENABLED
HA_BASE_URL
HA_TOKEN
HA_ENTITY_PREFIX
HA_SYNC_MS
HA_TIMEOUT_MS
```

Security defaults:

- `UNIFI_ALLOW_SELF_SIGNED=false`
- secrets and environment-specific addresses belong in ignored `.env` and
  private Compose overrides
- `.env`, data, certificates, private keys, logs, screenshots, and CodeGraph
  state are ignored
- the display browser receives normalized status only and needs no credential

## Mac Resume

From the cloned project root:

```bash
npm ci
npm test
npm run build
docker build -t ambient-ops:prototype .
docker run --rm -d --name ambient-ops-verify \
  -p 127.0.0.1:8791:8787 \
  -e DEMO_MODE=true \
  ambient-ops:prototype
curl http://127.0.0.1:8791/healthz
```

For physical HTC validation:

1. Confirm the device appears in `adb devices -l`.
2. Accept the Mac ADB RSA prompt if Android asks.
3. Use `adb reverse tcp:8791 tcp:8791`.
4. Open `http://127.0.0.1:8791/display/overview` in HTC Chrome.
5. Verify Overview, Network, Machines, machine selection, swipe navigation,
   fullscreen/immersive mode, wake behavior, and a physical 1280x720 screenshot.

## External Inputs

- Dedicated read-only UniFi API key.
- Private UniFi hostname/address selection and either the gateway certificate
  plus matching hostname, or an explicit trusted-LAN self-signed exception.
- Home Assistant long-lived access token if HA bridge is enabled.
- Synology Container Manager or SSH deployment authority.
- Apple signing identity remains on the primary Mac for any signed
  `codex-tps` artifact.
