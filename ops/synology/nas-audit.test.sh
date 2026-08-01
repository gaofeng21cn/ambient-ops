#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
AUDITOR=$SCRIPT_DIR/opl-nas-audit
INSTALLER=$SCRIPT_DIR/install-nas-audit-command.sh
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

checksum() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

auditor_checksum=$(checksum "$AUDITOR")
grep -F -x "EXPECTED_NAS_AUDIT_SHA256=$auditor_checksum" "$INSTALLER" >/dev/null

mkdir -p "$TEST_ROOT/bin"
cat > "$TEST_ROOT/proc-stat" <<'EOF'
cpu 1 2 3 4
btime 1785500000
EOF

cat > "$TEST_ROOT/bin/synowebapi" <<'EOF'
#!/bin/sh
set -eu
root=${OPL_NAS_AUDIT_TEST_ROOT:?}
[ -z "${DSM_SESSION_TOKEN:-}" ] || exit 98
printf '%s\n' 'synowebapi diagnostic name=private-task-a target=private-target-a' >&2
[ ! -f "$root/hard-fail-webapi" ] || exit 96
[ ! -f "$root/fail-webapi" ] || {
  printf '%s\n' '{"success":false,"error":{"code":1}}'
  exit 0
}
method=
task_id=
for argument in "$@"; do
  case "$argument" in
    method=*) method=${argument#method=} ;;
    task_id=*) task_id=${argument#task_id=} ;;
  esac
done
case "$method:$task_id" in
  list:)
    if [ -f "$root/no-tasks" ]; then
      printf '%s\n' '{"success":true,"data":{"tasks":[]}}'
      exit 0
    fi
    cat <<'JSON'
{"success":true,"data":{"tasks":[{"task_id":11,"name":"private-task-a","target":"private-target-a","last_bkp_result":"success","last_bkp_time":1785590000},{"task_id":22,"name":"private-task-b","target":"private-target-b","last_bkp_result":"failed","last_bkp_time":1785595000}]}}
JSON
    ;;
  status:11)
    printf '%s\n' '{"success":true,"data":{"task_id":11,"name":"private-task-a","last_bkp_result":"success","last_bkp_success_time":1785590000,"last_bkp_time":1785590000}}'
    ;;
  status:22)
    printf '%s\n' '{"success":true,"data":{"task_id":22,"name":"private-task-b","last_bkp_result":"failed","last_bkp_success_time":1785596400,"last_bkp_time":1785595000}}'
    ;;
  *)
    exit 97
    ;;
esac
EOF
chmod +x "$TEST_ROOT/bin/synowebapi"

export OPL_NAS_AUDIT_TEST_ROOT="$TEST_ROOT"
export OPL_NAS_AUDIT_TEST_JQ
OPL_NAS_AUDIT_TEST_JQ=$(command -v jq)
export OPL_NAS_AUDIT_TEST_NOW_EPOCH=1785600000
export DSM_SESSION_TOKEN=untrusted-session-token

stderr_file=$TEST_ROOT/auditor.stderr
output=$($AUDITOR status 2>"$stderr_file")
[ ! -s "$stderr_file" ] || {
  printf '%s\n' "NAS audit leaked WebAPI diagnostics" >&2
  exit 1
}
printf '%s\n' "$output" | jq -e '
  .schema == "opl_nas_audit.v1"
    and .scope == "synology-host"
    and .ok == true
    and .attentionRequired == false
    and .host.bootEpoch == 1785500000
    and .hyperBackup.configured == true
    and .hyperBackup.taskCount == 2
    and .hyperBackup.tasksWithRecordedSuccess == 2
    and .hyperBackup.latestSuccessEpoch == 1785596400
    and .hyperBackup.latestSuccessAgeSeconds == 3600
    and .hyperBackup.lastResults == {failed: 1, success: 1}
' >/dev/null

if printf '%s\n' "$output" | grep -E 'private-task|private-target|task_id' >/dev/null; then
  printf '%s\n' "NAS audit leaked task details" >&2
  exit 1
fi

touch "$TEST_ROOT/no-tasks"
empty_output=$($AUDITOR status)
printf '%s\n' "$empty_output" | jq -e '
  .ok == true
    and .attentionRequired == true
    and .hyperBackup.configured == false
    and .hyperBackup.taskCount == 0
    and .hyperBackup.latestSuccessAt == null
    and .hyperBackup.status == "not_configured"
' >/dev/null
rm -f "$TEST_ROOT/no-tasks"

touch "$TEST_ROOT/hard-fail-webapi"
hard_failure=
if hard_failure=$($AUDITOR status 2>&1); then
  printf '%s\n' "expected hard Hyper Backup API failure" >&2
  exit 1
fi
[ "$hard_failure" = "opl-nas-audit: Hyper Backup task list is unavailable" ] || {
  printf '%s\n' "NAS audit did not sanitize a hard WebAPI failure" >&2
  exit 1
}
rm -f "$TEST_ROOT/hard-fail-webapi"

touch "$TEST_ROOT/fail-webapi"
if $AUDITOR status >/dev/null 2>&1; then
  printf '%s\n' "expected Hyper Backup API failure" >&2
  exit 1
fi

if $AUDITOR status unexpected >/dev/null 2>&1; then
  printf '%s\n' "expected unexpected argument rejection" >&2
  exit 1
fi

printf '%s\n' "Synology NAS audit tests passed"
