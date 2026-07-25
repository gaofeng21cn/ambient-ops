#!/bin/zsh
set -u

ADB_PATH="${ADB_PATH:-/opt/homebrew/bin/adb}"
DEVICE_SERIAL="${ANDROID_SERIAL:-}"
KIOSK_COMPONENT="cn.gaofeng.ambientops.kiosk/.MainActivity"
REVERSE_SPEC="tcp:8791 tcp:8791"
configured_connection=0

adb_device() {
  if [[ -n "$DEVICE_SERIAL" ]]; then
    "$ADB_PATH" -s "$DEVICE_SERIAL" "$@"
  else
    "$ADB_PATH" "$@"
  fi
}

while true; do
  if [[ "$(adb_device get-state 2>/dev/null)" != "device" ]]; then
    configured_connection=0
    sleep 3
    continue
  fi

  if ! adb_device reverse --list 2>/dev/null | grep -Fq "$REVERSE_SPEC"; then
    adb_device reverse tcp:8791 tcp:8791 >/dev/null 2>&1 || true
  fi

  if [[ "$configured_connection" -eq 0 ]]; then
    home_component="$(adb_device shell cmd package resolve-activity --brief \
      -a android.intent.action.MAIN \
      -c android.intent.category.HOME 2>/dev/null | tail -n 1 | tr -d '\r')"
    if [[ "$home_component" != "$KIOSK_COMPONENT" ]]; then
      adb_device shell cmd package set-home-activity "$KIOSK_COMPONENT" >/dev/null 2>&1 || true
    fi
    adb_device shell settings put global stay_on_while_plugged_in 7 >/dev/null 2>&1 || true
    adb_device shell settings put system screen_off_timeout 2147483647 >/dev/null 2>&1 || true
    adb_device shell am start -n "$KIOSK_COMPONENT" >/dev/null 2>&1 || true
    configured_connection=1
  fi

  sleep 5
done
