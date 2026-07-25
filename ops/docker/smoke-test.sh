#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/ambient-ops-smoke.XXXXXX")
project_name="ambient-ops-smoke-$$"
image_name="${AMBIENT_OPS_SMOKE_IMAGE:-ambient-ops:smoke}"
package_version=$(CDPATH='' cd -- "$repo_root" && node -p "require('./package.json').version")

cleanup() {
  AMBIENT_OPS_SMOKE_SECRETS_DIR="$temporary_dir/secrets" \
  AMBIENT_OPS_SMOKE_IMAGE="$image_name" \
    docker compose \
      -f "$repo_root/compose.yaml" \
      -f "$repo_root/ops/docker/compose.smoke.yaml" \
      -p "$project_name" \
      down --volumes --remove-orphans >/dev/null 2>&1 || true
  case "$temporary_dir" in
    "${TMPDIR:-/tmp}"/ambient-ops-smoke.*)
      find "$temporary_dir" -depth -delete 2>/dev/null || true
      ;;
  esac
}
trap cleanup EXIT INT TERM

mkdir -p "$temporary_dir/secrets"
printf '%s\n' "ambient-ops-smoke-token" > "$temporary_dir/secrets/agent_push_token"
chmod 600 "$temporary_dir/secrets/agent_push_token"

compose() {
  AMBIENT_OPS_SMOKE_SECRETS_DIR="$temporary_dir/secrets" \
  AMBIENT_OPS_SMOKE_IMAGE="$image_name" \
    docker compose \
      -f "$repo_root/compose.yaml" \
      -f "$repo_root/ops/docker/compose.smoke.yaml" \
      -p "$project_name" \
      "$@"
}

wait_for_http() {
  url=$1
  attempts=0
  until curl --fail --silent "$url" >/dev/null; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 40 ]; then
      compose logs --no-color
      return 1
    fi
    sleep 1
  done
}

compose config --quiet
compose build \
  --build-arg "BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --build-arg "VCS_REF=$(git -C "$repo_root" rev-parse HEAD)" \
  --build-arg "VERSION=$package_version"
compose up --detach --wait --no-build

mapped_port=$(compose port ambient-ops 8787 | tail -n 1)
port=${mapped_port##*:}
base_url="http://127.0.0.1:$port"
wait_for_http "$base_url/healthz"

health_file="$temporary_dir/health.json"
status_file="$temporary_dir/status.json"
persisted_file="$temporary_dir/persisted.json"
served_sprite="$temporary_dir/spritesheet.webp"

curl --fail --silent --show-error "$base_url/healthz" > "$health_file"
node -e '
  const health = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  if (!health.ok || health.mode !== "live") {
    throw new Error("unexpected health payload: " + JSON.stringify(health));
  }
' "$health_file"

generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
curl --fail --silent --show-error \
  --request POST \
  --header "Authorization: Bearer ambient-ops-smoke-token" \
  --header "Content-Type: application/json" \
  --data-binary "{
    \"machineName\": \"Docker Smoke\",
    \"platform\": \"linux\",
    \"generatedAt\": \"$generated_at\",
    \"oneMinute\": {
      \"tps\": 12.5,
      \"inputTokens\": 540,
      \"cachedInputTokens\": 420,
      \"outputTokens\": 210,
      \"reasoningOutputTokens\": 55
    },
    \"fiveMinutes\": { \"tps\": 8.4 },
    \"activeSessions\": 2,
    \"pet\": {
      \"id\": \"ledger-owl\",
      \"displayName\": \"Ledger Owl\",
      \"spriteVersionNumber\": 1,
      \"state\": \"running\",
      \"stateSince\": \"$generated_at\"
    }
  }" \
  "$base_url/api/v1/agents/docker-smoke/snapshot" >/dev/null

curl --fail --silent --show-error "$base_url/api/status" > "$status_file"
node -e '
  const status = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  const machine = status.machines.find(({ machineId }) => machineId === "docker-smoke");
  if (!machine || machine.oneMinute.tps !== 12.5 || machine.pet?.id !== "ledger-owl") {
    throw new Error("agent snapshot missing from status: " + JSON.stringify(status));
  }
' "$status_file"

curl --fail --silent --show-error "$base_url/display/pet" | grep -q '<div id="root"></div>'
curl --fail --silent --show-error "$base_url/pets/ledger-owl/spritesheet.webp" > "$served_sprite"
cmp "$repo_root/public/pets/ledger-owl/spritesheet.webp" "$served_sprite"

container_id=$(compose ps --quiet ambient-ops)
docker exec "$container_id" test -s /data/state.json
if docker exec "$container_id" touch /app/should-not-be-writable 2>/dev/null; then
  echo "container root filesystem is unexpectedly writable" >&2
  exit 1
fi

compose restart ambient-ops
mapped_port=$(compose port ambient-ops 8787 | tail -n 1)
port=${mapped_port##*:}
base_url="http://127.0.0.1:$port"
wait_for_http "$base_url/healthz"
curl --fail --silent --show-error "$base_url/api/status" > "$persisted_file"
node -e '
  const status = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  const machine = status.machines.find(({ machineId }) => machineId === "docker-smoke");
  if (!machine || machine.pet?.state !== "running") {
    throw new Error("snapshot did not survive restart: " + JSON.stringify(status));
  }
' "$persisted_file"

echo "Ambient Ops Docker smoke test passed at $base_url"
