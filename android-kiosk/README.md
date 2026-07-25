# Ambient Ops Android Kiosk

This small native Android application owns the HTC display surface. It discovers
`_ambient-ops._tcp.local` with Android NSD, remembers the last successful
instance and LAN endpoint, keeps the screen awake, restores immersive mode,
retries after connection failures, and can act as the default Home application.
Normal operation does not require USB or `adb reverse`.

Build and install:

```bash
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell cmd package set-home-activity cn.gaofeng.ambientops.kiosk/.MainActivity
adb shell am start -n cn.gaofeng.ambientops.kiosk/.MainActivity
```

Store a manual rescue URL and preferred instance without rebuilding:

```bash
adb shell am start -n cn.gaofeng.ambientops.kiosk/.MainActivity \
  --es ambient_ops_url http://192.168.1.10:8787/display/overview \
  --es ambient_ops_instance_id home-ops
```

Restore the HTC launcher:

```bash
adb shell cmd package set-home-activity com.htc.launcher/.Launcher
adb shell am start -n com.htc.launcher/.Launcher
```
