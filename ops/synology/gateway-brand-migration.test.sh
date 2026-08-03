#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)

command -v docker >/dev/null 2>&1 || {
  printf '%s\n' "Docker is unavailable; skipping Compose compatibility test"
  exit 0
}

legacy_env=$(mktemp)
trap 'rm -f "$legacy_env"' EXIT HUP INT TERM
cat > "$legacy_env" <<'EOF'
AMBIENT_OPS_IMAGE=ghcr.io/gaofeng21cn/ambient-ops:0.1.38
OPL_FLEET_COCKPIT_DATA_VOLUME=ambient-ops_ambient_ops_data
EOF

rendered=$(docker compose --env-file "$legacy_env" -f "$REPO_ROOT/compose.yaml" config --format json)
printf '%s\n' "$rendered" | jq -e '
  .services.gateway.image == "ghcr.io/gaofeng21cn/ambient-ops:0.1.38"
    and .volumes.cockpit_data.name == "ambient-ops_ambient_ops_data"
    and (.services["ambient-ops"] == null)
' >/dev/null

printf '%s\n' "Compose legacy identity compatibility test passed"
