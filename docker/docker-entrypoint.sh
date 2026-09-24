#!/bin/sh
# Ensure bind mounts / volumes are writable by giftistry (mirrors NixOS tmpfiles ownership).
set -eu

STATE_DIR="${GIFTISTRY_STATE_DIR:-/var/lib/giftistry}"
CONFIG_PATH="${GIFTISTRY_CONFIG_PATH:-/etc/giftistry/config.json}"
CONFIG_DIR="$(dirname "$CONFIG_PATH")"

mkdir -p "$STATE_DIR" "$CONFIG_DIR"
chown -R giftistry:giftistry "$STATE_DIR" || true
chown giftistry:giftistry "$CONFIG_DIR" || true
if [ -e "$CONFIG_PATH" ]; then
  chown giftistry:giftistry "$CONFIG_PATH" || true
  chmod u+rw "$CONFIG_PATH" || true
fi

exec runuser -u giftistry -- "$@"
