#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
KEYSTORE_PATH="${AMBIENT_OPS_ANDROID_KEYSTORE:-$HOME/Library/Application Support/Ambient Ops/android-signing/ambient-ops-release.p12}"
KEYCHAIN_SERVICE="${AMBIENT_OPS_ANDROID_KEYCHAIN_SERVICE:-cn.gaofeng.ambient-ops.android-signing}"
KEYCHAIN_ACCOUNT="${AMBIENT_OPS_ANDROID_KEYCHAIN_ACCOUNT:-${USER:-}}"
KEY_ALIAS="${AMBIENT_OPS_ANDROID_KEY_ALIAS:-ambient-ops}"
HOMEBREW_JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
HOMEBREW_ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"

if [[ -z "$KEYCHAIN_ACCOUNT" ]]; then
  echo "Unable to determine the Keychain account." >&2
  exit 1
fi
if [[ ! -f "$KEYSTORE_PATH" ]]; then
  echo "Android release keystore not found: $KEYSTORE_PATH" >&2
  exit 1
fi
if [[ -z "${JAVA_HOME:-}" && -d "$HOMEBREW_JAVA_HOME" ]]; then
  export JAVA_HOME="$HOMEBREW_JAVA_HOME"
fi
if [[ -z "${ANDROID_HOME:-}" && -d "$HOMEBREW_ANDROID_HOME" ]]; then
  export ANDROID_HOME="$HOMEBREW_ANDROID_HOME"
fi

SIGNING_PASSWORD="$(
  /usr/bin/security find-generic-password \
    -a "$KEYCHAIN_ACCOUNT" \
    -s "$KEYCHAIN_SERVICE" \
    -w
)"

export AMBIENT_OPS_ANDROID_KEYSTORE="$KEYSTORE_PATH"
export AMBIENT_OPS_ANDROID_KEYSTORE_PASSWORD="$SIGNING_PASSWORD"
export AMBIENT_OPS_ANDROID_KEY_ALIAS="$KEY_ALIAS"
export AMBIENT_OPS_ANDROID_KEY_PASSWORD="$SIGNING_PASSWORD"

exec "$ROOT_DIR/gradlew" \
  -p "$ROOT_DIR" \
  :app:testReleaseUnitTest \
  :app:assembleRelease
