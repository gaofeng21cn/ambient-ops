#!/bin/sh

set -eu

umask 077
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH

PROGRAM=install-nas-audit-command.sh
DEPLOY_USER=gaofeng
INSTALL_PATH=/usr/local/sbin/opl-nas-audit
SUDOERS_PATH=/etc/sudoers.d/opl-nas-audit
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
AUDITOR_SOURCE=$SCRIPT_DIR/opl-nas-audit
EXPECTED_NAS_AUDIT_SHA256=3388000acc86ce14fa6f831403217d5b40fe07945ad1b0ed0eb7908329081269

fail() {
  printf '%s\n' "$PROGRAM: $*" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || fail "must be run once as root"
[ -f "$AUDITOR_SOURCE" ] && [ ! -L "$AUDITOR_SOURCE" ] || fail "staged NAS auditor is missing"
[ -d /etc/sudoers.d ] || fail "/etc/sudoers.d is unavailable"
[ ! -L "$INSTALL_PATH" ] || fail "install path must not be a symbolic link"
[ ! -L "$SUDOERS_PATH" ] || fail "sudoers path must not be a symbolic link"

/usr/bin/install -d -o root -g root -m 0755 /usr/local/sbin

auditor_stage=/usr/local/sbin/.opl-nas-audit.install.$$
auditor_backup=/usr/local/sbin/.opl-nas-audit.previous.$$
sudoers_temp=/etc/sudoers.d/.opl-nas-audit.$$
sudoers_backup=/etc/sudoers.d/.opl-nas-audit.previous.$$
had_auditor=false
had_sudoers=false
committed=false

rollback() {
  exit_code=$?
  trap - EXIT HUP INT TERM
  rm -f "$auditor_stage" "$sudoers_temp"
  if [ "$committed" != true ]; then
    if [ "$had_auditor" = true ]; then
      mv -f "$auditor_backup" "$INSTALL_PATH"
    else
      rm -f "$INSTALL_PATH"
    fi
    if [ "$had_sudoers" = true ]; then
      mv -f "$sudoers_backup" "$SUDOERS_PATH"
    else
      rm -f "$SUDOERS_PATH"
    fi
  fi
  rm -f "$auditor_backup" "$sudoers_backup"
  exit "$exit_code"
}

trap rollback EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

/usr/bin/install -o root -g root -m 0700 "$AUDITOR_SOURCE" "$auditor_stage"
printf '%s  %s\n' "$EXPECTED_NAS_AUDIT_SHA256" "$auditor_stage" |
  /usr/bin/sha256sum -c - >/dev/null || fail "staged NAS auditor checksum does not match the reviewed artifact"

if [ -e "$INSTALL_PATH" ]; then
  cp "$INSTALL_PATH" "$auditor_backup"
  had_auditor=true
fi
if [ -e "$SUDOERS_PATH" ]; then
  cp "$SUDOERS_PATH" "$sudoers_backup"
  had_sudoers=true
fi

/usr/bin/install -o root -g root -m 0755 "$auditor_stage" "$INSTALL_PATH"

printf '%s ALL=(root) NOPASSWD: %s status\n' "$DEPLOY_USER" "$INSTALL_PATH" > "$sudoers_temp"
chown root:root "$sudoers_temp"
chmod 0440 "$sudoers_temp"
mv -f "$sudoers_temp" "$SUDOERS_PATH"

if ! /usr/bin/sudo -n -l -U "$DEPLOY_USER" 2>&1 | grep -F "$INSTALL_PATH status" >/dev/null; then
  fail "sudo did not accept the restricted NAS audit rule"
fi

"$INSTALL_PATH" status >/dev/null

committed=true
rm -f "$auditor_stage" "$auditor_backup" "$sudoers_backup"
trap - EXIT HUP INT TERM

printf '%s\n' "$PROGRAM: installed restricted NAS audit command for $DEPLOY_USER"
printf '%s\n' "$PROGRAM: next: sudo -n $INSTALL_PATH status"
