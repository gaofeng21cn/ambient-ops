#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)
DEPLOYER=$SCRIPT_DIR/ambient-ops-deploy
INSTALLER=$SCRIPT_DIR/install-deploy-command.sh
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

checksum() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

deployer_checksum=$(checksum "$DEPLOYER")
compose_checksum=$(checksum "$REPO_ROOT/compose.yaml")
grep -F -x "EXPECTED_DEPLOYER_SHA256=$deployer_checksum" "$INSTALLER" >/dev/null
grep -F -x "EXPECTED_COMPOSE_SHA256=$compose_checksum" "$INSTALLER" >/dev/null

mkdir -p "$TEST_ROOT/managed/secrets" "$TEST_ROOT/managed/state" "$TEST_ROOT/bin"
cp "$REPO_ROOT/compose.yaml" "$TEST_ROOT/managed/compose.yaml"
cat > "$TEST_ROOT/proc-stat" <<'EOF'
cpu 1 2 3 4
btime 1785500000
EOF
cat > "$TEST_ROOT/managed/.env" <<'EOF'
AMBIENT_OPS_IMAGE=ghcr.io/gaofeng21cn/ambient-ops:0.1.25
DEMO_MODE=false
SITE_NAME=Test
DISPLAY_TIME_ZONE=UTC
INSTANCE_ID=test-instance
DISCOVERY_ENABLED=true
EOF
printf 'token\n' > "$TEST_ROOT/managed/secrets/agent_push_token"

cat > "$TEST_ROOT/bin/flock" <<'EOF'
#!/bin/sh
exit 0
EOF

cat > "$TEST_ROOT/bin/sha256sum" <<'EOF'
#!/bin/sh
exec /usr/bin/shasum -a 256 "$@"
EOF

cat > "$TEST_ROOT/bin/docker" <<'EOF'
#!/bin/sh
set -eu
root=${AMBIENT_OPS_DEPLOY_TEST_ROOT:?}
[ -z "${DOCKER_HOST:-}" ] || exit 98
[ -z "${COMPOSE_FILE:-}" ] || exit 98
command_name=${1:-}
case "$command_name" in
  pull)
    printf '%s\n' "$2" > "$root/pulled-image"
    ;;
  image)
    format=
    previous=
    image_ref=
    for argument in "$@"; do
      if [ "$previous" = --format ]; then format=$argument; fi
      previous=$argument
      image_ref=$argument
    done
    image=$(awk -F= '$1 == "AMBIENT_OPS_IMAGE" { sub(/^[^=]*=/, ""); print; exit }' "$root/managed/.env")
    case "$format" in
      *'json .RepoDigests'*)
        digest=${image##*@}
        printf '["ghcr.io/gaofeng21cn/ambient-ops@%s"]\n' "$digest"
        ;;
      *)
        digest=${image_ref##*@}
        printf 'ghcr.io/gaofeng21cn/ambient-ops@%s\n' "$digest"
        ;;
    esac
    ;;
  inspect)
    format=
    previous=
    for argument in "$@"; do
      if [ "$previous" = --format ]; then format=$argument; fi
      previous=$argument
    done
    image=$(awk -F= '$1 == "AMBIENT_OPS_IMAGE" { sub(/^[^=]*=/, ""); print; exit }' "$root/managed/.env")
    case "$format" in
      '{{.Config.Image}}') printf '%s\n' "$image" ;;
      '{{.Image}}') printf '%s\n' 'sha256:runtime-image-id' ;;
      '{{.Name}}') printf '%s\n' '/ambient-ops-ambient-ops-1' ;;
      '{{.State.Status}}') printf '%s\n' 'running' ;;
      '{{.State.Running}}') printf '%s\n' 'true' ;;
      '{{.State.StartedAt}}') printf '%s\n' '2026-08-01T06:00:00.123456789Z' ;;
      '{{.HostConfig.RestartPolicy.Name}}') printf '%s\n' 'unless-stopped' ;;
      '{{json .Mounts}}')
        printf '%s\n' '[{"Type":"volume","Name":"ambient-ops_ambient_ops_data","Source":"/private/docker/path","Destination":"/data","RW":true}]'
        ;;
      *) exit 96 ;;
    esac
    ;;
  compose)
    action=
    format=
    for argument in "$@"; do
      case "$argument" in
        config|pull|up|ps) action=$argument ;;
        json) format=json ;;
      esac
    done
    if [ "$action" = config ] && [ "$format" = json ]; then
      image=$(awk -F= '$1 == "AMBIENT_OPS_IMAGE" { sub(/^[^=]*=/, ""); print; exit }' "$root/managed/.env")
      cat <<JSON
{"services":{"ambient-ops":{"image":"$image","network_mode":"host","restart":"unless-stopped","read_only":true,"ports":null,"build":null,"environment":{"DEMO_MODE":"false","DISCOVERY_ENABLED":"true"},"volumes":[{"type":"bind","source":"$root/managed/secrets","target":"/run/secrets","read_only":true}]}}}
JSON
    elif [ "$action" = ps ]; then
      printf '%s\n' 'container-id'
    elif [ "$action" = up ]; then
      if [ -f "$root/fail-up-once" ]; then
        rm -f "$root/fail-up-once"
        exit 1
      fi
      printf 'up\n' >> "$root/actions"
    fi
    ;;
  *)
    exit 1
    ;;
esac
EOF

cat > "$TEST_ROOT/bin/curl" <<'EOF'
#!/bin/sh
set -eu
root=${AMBIENT_OPS_DEPLOY_TEST_ROOT:?}
[ -z "${HTTP_PROXY:-}" ] || exit 98
[ -z "${http_proxy:-}" ] || exit 98
[ ! -f "$root/fail-health" ] || exit 22
url=
for argument in "$@"; do
  case "$argument" in http://*) url=$argument ;; esac
done
if [ "${url##*/}" = healthz ]; then
  printf '%s\n' '{"ok":true,"mode":"live","network":"live","codex":"live","machines":3}'
else
  image=$(awk -F= '$1 == "AMBIENT_OPS_IMAGE" { sub(/^[^=]*=/, ""); print; exit }' "$root/managed/.env")
  version=${image#ghcr.io/gaofeng21cn/ambient-ops:}
  version=${version%@*}
  printf '{"schemaVersion":1,"serverVersion":"%s","demo":false,"instanceId":"test-instance","capabilities":{"loadVisualState":true},"machines":[{}]}\n' "$version"
fi
EOF

chmod +x "$TEST_ROOT/bin/"*

export AMBIENT_OPS_DEPLOY_TEST_ROOT="$TEST_ROOT"
export AMBIENT_OPS_DEPLOY_TEST_JQ
AMBIENT_OPS_DEPLOY_TEST_JQ=$(command -v jq)
export DOCKER_HOST=tcp://untrusted.example:2375
export COMPOSE_FILE=/tmp/untrusted-compose.yaml
export HTTP_PROXY=http://untrusted.example:8080
export http_proxy=http://untrusted.example:8080

"$DEPLOYER" --check

DIGEST=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
"$DEPLOYER" deploy 0.1.26 "$DIGEST"
grep -F -x "AMBIENT_OPS_IMAGE=ghcr.io/gaofeng21cn/ambient-ops:0.1.26@$DIGEST" "$TEST_ROOT/managed/.env"

cp "$TEST_ROOT/managed/.env" "$TEST_ROOT/success.env"
touch "$TEST_ROOT/fail-up-once"
if "$DEPLOYER" deploy 0.1.27 sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; then
  printf '%s\n' "expected failed deployment" >&2
  exit 1
fi
cmp "$TEST_ROOT/success.env" "$TEST_ROOT/managed/.env"

cat > "$TEST_ROOT/managed/state/current" <<EOF
version=0.1.26
digest=$DIGEST
image=ghcr.io/gaofeng21cn/ambient-ops:0.1.26@$DIGEST
deployed_at=2026-07-01T00:00:00Z
EOF
status=$($DEPLOYER status)
printf '%s\n' "$status" | jq -e \
  --arg digest "$DIGEST" '
    .schema == "opl_fleet_cockpit_gateway_status.v1"
      and .product == "OPL Fleet Cockpit"
      and .service == "OPL Fleet Telemetry Gateway"
      and .compatibilityId == "ambient-ops"
      and .ok == true
      and .image.indexDigest == $digest
      and .image.digestVerified == true
      and .container.id == "container-id"
      and .container.restartPolicy == "unless-stopped"
      and .container.dataMount.name == "ambient-ops_ambient_ops_data"
      and .host.rebootRecovery.verified == true
  ' >/dev/null

if printf '%s\n' "$status" | grep -F '/private/docker/path' >/dev/null; then
  printf '%s\n' "deployment status leaked the host volume path" >&2
  exit 1
fi

sed 's/^deployed_at=.*/deployed_at=2026-08-01T05:50:00Z/' \
  "$TEST_ROOT/managed/state/current" > "$TEST_ROOT/managed/state/current.new"
mv "$TEST_ROOT/managed/state/current.new" "$TEST_ROOT/managed/state/current"
post_boot_status=$($DEPLOYER status)
printf '%s\n' "$post_boot_status" | jq -e '
  .ok == true
    and .host.rebootRecovery.verified == false
    and .host.rebootRecovery.reason == "current_release_deployed_after_host_boot"
' >/dev/null

if "$DEPLOYER" deploy latest "$DIGEST"; then
  printf '%s\n' "expected invalid version rejection" >&2
  exit 1
fi
if "$DEPLOYER" deploy 0.1.27 'sha256:not-a-digest'; then
  printf '%s\n' "expected invalid digest rejection" >&2
  exit 1
fi

printf '%s\n' "Synology deploy tests passed"
