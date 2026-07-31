# Ambient Ops for iOS

Ambient Ops for iOS is a native companion for the self-hosted Ambient Ops server.
It reads the versioned `/api/v1/status` endpoint and does not embed the browser
dashboard.

## Product surfaces

- Home summarizes the most important Codex, host, and network state.
- Machines orders unavailable and constrained hosts before normal activity.
- Display provides native Overview, Network, Load, and Pet presentations.
- The Load foreground animation is rendered with SpriteKit from the server-owned
  `loadVisualState`; its work packets are an aggregate metaphor, not individual
  conversations.
- Widgets, Live Activities, Dynamic Island, and StandBy use a lightweight
  representation of the same focused-host state.
- User-facing navigation, settings, connection, permission, empty-state, Widget,
  and Live Activity text supports English and Simplified Chinese. English is the
  development and fallback language; the app otherwise follows the system language.

## Demo Mode

Demo Mode is enabled on first launch and requires no server, account, or network
permission. It includes deterministic coverage for:

- quiet, active, heavy, and constrained load;
- live and stale machines;
- known and unavailable CPU telemetry;
- a configured pet and an unconfigured-pet state; and
- network throughput history.

This is also the complete App Review path. Reviewers can inspect all core user
interfaces before connecting a local server.

## Connecting a server

1. Open Settings.
2. Enter a server URL and choose Connect, or choose Find on Local Network.
3. The app explains why local-network access is needed before Bonjour discovery
   triggers the system permission dialog.

Turning Demo Mode off follows the same path: it clears demo metrics immediately,
reuses a saved server address when available, or offers local-network discovery
when no server has been configured.

Discovery uses `_ambient-ops._tcp`. The app requests only the public aggregate
status endpoint. Server, Codex TPS, and router credentials remain outside the app.

## Live Activity boundary

The user explicitly starts and ends a Live Activity from Settings. While the app
can refresh, it updates the current activity locally. Background near-real-time
updates require an optional APNs relay, which is not part of the first self-hosted
client release and is advertised by the server as `liveActivityPush: false`.

The relay must never place an APNs `.p8` signing key in the app or on a public NAS
endpoint. A future relay should send only instance, focused-host, load-state,
aggregate TPS/session/CPU values, and timestamps, with state-change throttling.

## Build

The Xcode project is generated with XcodeGen:

```bash
cd ios-app
xcodegen generate
open AmbientOps.xcodeproj
```

The app and widget use:

- App bundle ID: `cn.gaofeng.ambientops`
- Widget bundle ID: `cn.gaofeng.ambientops.widgets`
- App Group: `group.cn.gaofeng.ambientops`
- Team: `SVVC4TA784`
- Minimum iOS version: iOS 18

Automatic signing must create or resolve the App ID, Widget App ID, and App Group
for the selected Apple Developer Program team before a device archive is valid.
