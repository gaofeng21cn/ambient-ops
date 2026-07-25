# macOS and HTC kiosk runtime

The permanent runtime has one required user LaunchAgent:

- `cn.gaofeng.ambient-ops.server` runs the built Ambient Ops server from
  `~/Library/Application Support/Ambient Ops/runtime`, not from a Git checkout.

Install a tested release and atomically switch the runtime:

```bash
./ops/macos/install-runtime.sh <release-id>
```

The installer preserves the previous release for rollback, switches
`runtime/current`, restarts the server LaunchAgent, and requires a successful
`/healthz` readback. Credentials remain in Keychain and normalized data remains
in the existing data directory.

Codex TPS now discovers Ambient Ops and pushes aggregate metrics from the
menu-bar application. The legacy `cn.gaofeng.ambient-ops.codex-tps-agent`
LaunchAgent is kept as a recovery artifact but must remain disabled to avoid
counting the same Mac twice.

Agent entries remain visible during the configured stale grace period. After
`STALE_AFTER_SECONDS` without a new snapshot, Ambient Ops removes the inactive
machine from both the dashboard and persisted state.

The server receives Keychain service names in its environment. Secret values
are not stored in plist files, logs, or the repository.

The HTC application is built from [`../android-kiosk`](../android-kiosk/README.md).
It is the default Home application, owns an immersive WebView, keeps the display
awake, discovers `_ambient-ops._tcp.local`, and retries after service or network
changes. Normal operation does not require USB or ADB reverse.

The `cn.gaofeng.ambient-ops.adb-kiosk` LaunchAgent and `adb-kiosk-watch.sh` are
recovery tools only. They must remain unloaded during normal operation so an
ADB reverse tunnel cannot hide a broken LAN discovery path.

To intentionally return the device to the HTC launcher:

```bash
adb shell cmd package set-home-activity com.htc.launcher/.Launcher
adb shell am start -n com.htc.launcher/.Launcher
```

For a bounded USB recovery session only:

```bash
launchctl bootstrap gui/$(id -u) \
  ~/Library/LaunchAgents/cn.gaofeng.ambient-ops.adb-kiosk.plist
```
