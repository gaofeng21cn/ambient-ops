#!/bin/sh

set -eu

umask 077
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH

PROGRAM=install-deploy-command.sh
DEPLOY_USER=gaofeng
SOURCE_PROJECT=/volume1/docker/ambient-ops
MANAGED_DIR=/volume1/.ambient-ops-deploy
STATE_DIR=$MANAGED_DIR/state
INSTALL_PATH=/usr/local/sbin/ambient-ops-deploy
SUDOERS_PATH=/etc/sudoers.d/ambient-ops-deploy
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
DEPLOYER_SOURCE=$SCRIPT_DIR/ambient-ops-deploy
COMPOSE_SOURCE=$SCRIPT_DIR/compose.yaml
EXPECTED_DEPLOYER_SHA256=ddfce5ba06889737f84739ce887af7008aac017195b3e8d3d15df07d0b15e1f3
EXPECTED_COMPOSE_SHA256=38a7e6a3bc13db7d04126d5984b2ca3e793dda97379693a1c639055d25d423d9

log() {
  printf '%s\n' "$PROGRAM: $*"
}

fail() {
  printf '%s\n' "$PROGRAM: $*" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || fail "must be run once as root"
[ -f "$DEPLOYER_SOURCE" ] && [ ! -L "$DEPLOYER_SOURCE" ] || fail "staged deployer is missing"
[ -f "$COMPOSE_SOURCE" ] && [ ! -L "$COMPOSE_SOURCE" ] || fail "staged compose.yaml is missing"
[ -f "$SOURCE_PROJECT/.env" ] && [ ! -L "$SOURCE_PROJECT/.env" ] || fail "source .env is missing"
[ -d "$SOURCE_PROJECT/secrets" ] && [ ! -L "$SOURCE_PROJECT/secrets" ] || fail "source secrets directory is missing"
[ -d /etc/sudoers.d ] || fail "/etc/sudoers.d is unavailable"

for managed_path in "$MANAGED_DIR" "$MANAGED_DIR/.env" "$MANAGED_DIR/compose.yaml" "$MANAGED_DIR/secrets" "$STATE_DIR"; do
  [ ! -L "$managed_path" ] || fail "managed paths must not be symbolic links: $managed_path"
done

/usr/bin/install -d -o root -g root -m 0700 "$MANAGED_DIR"
/usr/bin/install -d -o root -g root -m 0700 "$STATE_DIR"

deployer_stage=$STATE_DIR/deployer.install.$$
compose_stage=$STATE_DIR/compose.install.$$
/usr/bin/install -o root -g root -m 0700 "$DEPLOYER_SOURCE" "$deployer_stage"
/usr/bin/install -o root -g root -m 0600 "$COMPOSE_SOURCE" "$compose_stage"

printf '%s  %s\n' "$EXPECTED_DEPLOYER_SHA256" "$deployer_stage" | /usr/bin/sha256sum -c - >/dev/null ||
  fail "staged deployer checksum does not match the reviewed artifact"
printf '%s  %s\n' "$EXPECTED_COMPOSE_SHA256" "$compose_stage" | /usr/bin/sha256sum -c - >/dev/null ||
  fail "staged compose.yaml checksum does not match the reviewed artifact"

if [ ! -e "$MANAGED_DIR/.env" ]; then
  /usr/bin/install -o root -g root -m 0600 "$SOURCE_PROJECT/.env" "$MANAGED_DIR/.env"
fi

/usr/bin/install -o root -g root -m 0644 "$compose_stage" "$MANAGED_DIR/compose.yaml"

if [ ! -e "$MANAGED_DIR/secrets" ]; then
  /usr/bin/install -d -o 1000 -g 1000 -m 0700 "$MANAGED_DIR/secrets"
fi

secret_path=
for secret_path in "$SOURCE_PROJECT/secrets"/*; do
  [ -e "$secret_path" ] || continue
  [ -f "$secret_path" ] && [ ! -L "$secret_path" ] || fail "source secret entries must be regular files"
  managed_secret=$MANAGED_DIR/secrets/$(basename "$secret_path")
  if [ ! -e "$managed_secret" ]; then
    /usr/bin/install -o 1000 -g 1000 -m 0600 "$secret_path" "$MANAGED_DIR/secrets/$(basename "$secret_path")"
  fi
done
chown 1000:1000 "$MANAGED_DIR/secrets"
chmod 0700 "$MANAGED_DIR/secrets"
for secret_path in "$MANAGED_DIR/secrets"/*; do
  [ -e "$secret_path" ] || continue
  [ -f "$secret_path" ] && [ ! -L "$secret_path" ] || fail "managed secret entries must be regular files"
  chown 1000:1000 "$secret_path"
  chmod 0600 "$secret_path"
done

/usr/bin/install -d -o root -g root -m 0755 /usr/local/sbin
/usr/bin/install -o root -g root -m 0755 "$deployer_stage" "$INSTALL_PATH"
rm -f "$deployer_stage" "$compose_stage"

# The old project remains a recoverable source copy, but its secrets are no
# longer world-readable. The privileged deployer never reads this directory.
chmod 0755 "$SOURCE_PROJECT"
chmod 0600 "$SOURCE_PROJECT/.env"
chmod 0700 "$SOURCE_PROJECT/secrets"
for secret_path in "$SOURCE_PROJECT/secrets"/*; do
  [ -e "$secret_path" ] || continue
  chmod 0600 "$secret_path"
done

sudoers_temp=/etc/sudoers.d/.ambient-ops-deploy.$$
sudoers_backup=
if [ -e "$SUDOERS_PATH" ]; then
  sudoers_backup=$STATE_DIR/sudoers.previous.$$
  cp "$SUDOERS_PATH" "$sudoers_backup"
fi

printf '%s ALL=(root) NOPASSWD: %s\n' "$DEPLOY_USER" "$INSTALL_PATH" > "$sudoers_temp"
chown root:root "$sudoers_temp"
chmod 0440 "$sudoers_temp"
mv -f "$sudoers_temp" "$SUDOERS_PATH"

if ! /usr/bin/sudo -n -l -U "$DEPLOY_USER" 2>&1 | grep -F "$INSTALL_PATH" >/dev/null; then
  rm -f "$SUDOERS_PATH"
  if [ -n "$sudoers_backup" ]; then
    cp "$sudoers_backup" "$SUDOERS_PATH"
    chown root:root "$SUDOERS_PATH"
    chmod 0440 "$SUDOERS_PATH"
  fi
  fail "sudo did not accept the restricted rule; the previous rule was restored"
fi

rm -f "$sudoers_backup"
"$INSTALL_PATH" --check

log "installed restricted deploy command for $DEPLOY_USER"
log "next: sudo -n $INSTALL_PATH --check"
