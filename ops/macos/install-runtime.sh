#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h:h}"
RUNTIME_ROOT="${AMBIENT_OPS_RUNTIME_ROOT:-$HOME/Library/Application Support/Ambient Ops/runtime}"
RELEASE_ID="${1:-$(date -u +%Y%m%d-%H%M%S)}"
RELEASES_DIR="$RUNTIME_ROOT/releases"
RELEASE_DIR="$RELEASES_DIR/$RELEASE_ID"
STAGING_DIR="$RELEASES_DIR/.staging-$RELEASE_ID"
CURRENT_LINK="$RUNTIME_ROOT/current"
LAUNCH_LABEL="cn.gaofeng.ambient-ops.server"
HEALTH_URL="${AMBIENT_OPS_HEALTH_URL:-http://127.0.0.1:8791/healthz}"

if [[ ! "$RELEASE_ID" =~ '^[A-Za-z0-9._-]{1,80}$' ]]; then
  echo "Release ID must contain only letters, numbers, dots, underscores, or hyphens." >&2
  exit 1
fi
if [[ -e "$RELEASE_DIR" || -L "$RELEASE_DIR" ]]; then
  echo "Release already exists: $RELEASE_DIR" >&2
  exit 1
fi

mkdir -p "$RELEASES_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cd "$ROOT_DIR"
npm ci
npm test
npm run build

ditto "$ROOT_DIR/dist" "$STAGING_DIR/dist"
ditto "$ROOT_DIR/server" "$STAGING_DIR/server"
ditto "$ROOT_DIR/package.json" "$STAGING_DIR/package.json"
ditto "$ROOT_DIR/package-lock.json" "$STAGING_DIR/package-lock.json"

cd "$STAGING_DIR"
npm ci --omit=dev --ignore-scripts
test -f "$STAGING_DIR/dist/pets/ledger-owl/spritesheet.webp"

mv "$STAGING_DIR" "$RELEASE_DIR"
PREVIOUS_TARGET="$(readlink "$CURRENT_LINK" 2>/dev/null || true)"
ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"

if ! launchctl kickstart -k "gui/$(id -u)/$LAUNCH_LABEL"; then
  if [[ -n "$PREVIOUS_TARGET" ]]; then
    ln -sfn "$PREVIOUS_TARGET" "$CURRENT_LINK"
    launchctl kickstart -k "gui/$(id -u)/$LAUNCH_LABEL" || true
  fi
  exit 1
fi

for attempt in {1..20}; do
  if curl -fsS "$HEALTH_URL" >/dev/null; then
    echo "$RELEASE_DIR"
    exit 0
  fi
  sleep 1
done

if [[ -n "$PREVIOUS_TARGET" ]]; then
  ln -sfn "$PREVIOUS_TARGET" "$CURRENT_LINK"
  launchctl kickstart -k "gui/$(id -u)/$LAUNCH_LABEL" || true
fi
echo "Health check failed after switching to $RELEASE_ID; previous runtime restored." >&2
exit 1
