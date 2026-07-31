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
    image_ref=
    for argument in "$@"; do image_ref=$argument; done
    digest=${image_ref##*@}
    printf 'ghcr.io/gaofeng21cn/ambient-ops@%s\n' "$digest"
    ;;
  compose)
    action=
    format=
    for argument in "$@"; do
      case "$argument" in
        config|pull|up) action=$argument ;;
        json) format=json ;;
      esac
    done
    if [ "$action" = config ] && [ "$format" = json ]; then
      image=$(awk -F= '$1 == "AMBIENT_OPS_IMAGE" { sub(/^[^=]*=/, ""); print; exit }' "$root/managed/.env")
      cat <<JSON
{"services":{"ambient-ops":{"image":"$image","network_mode":"host","restart":"unless-stopped","read_only":true,"ports":null,"build":null,"environment":{"DEMO_MODE":"false","DISCOVERY_ENABLED":"true"},"volumes":[{"type":"bind","source":"$root/managed/secrets","target":"/run/secrets","read_only":true}]}}}
JSON
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

if "$DEPLOYER" deploy latest "$DIGEST"; then
  printf '%s\n' "expected invalid version rejection" >&2
  exit 1
fi
if "$DEPLOYER" deploy 0.1.27 'sha256:not-a-digest'; then
  printf '%s\n' "expected invalid digest rejection" >&2
  exit 1
fi

printf '%s\n' "Synology deploy tests passed"
