#!/usr/bin/env bash
#
# Install the LG lockout bundle on one or more rooted webOS TVs.
#
# Usage:
#   ./install.sh root@192.168.178.138 root@192.168.178.33
#   ./install.sh --reboot 192.168.178.138
#
# Supplying only an IP address implies the root user. The optional --reboot
# verifies that all Homebrew startup hooks survive a complete boot.
#
# This is the strict profile: LG Content Store, LG Shop, and LG voice search
# are blocked, while unrelated streaming destinations remain available. A
# factory reset removes all on-TV protection, and LG can change its hardcoded
# endpoint IPs, so periodically review and re-verify the list.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD_DIR="$SCRIPT_DIR/tv"
REBOOT=0
TARGETS=()

SSH_OPTIONS=(
  -o BatchMode=yes
  -o ConnectTimeout=10
)

usage() {
  cat <<'EOF'
Usage: install.sh [--reboot] <root@TV-or-IP> [<root@TV-or-IP> ...]

Options:
  --reboot  Reboot each TV after installation and verify startup persistence.
  -h        Show this help.
EOF
}

while (($#)); do
  case "$1" in
    --reboot)
      REBOOT=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while (($#)); do
        TARGETS+=("$1")
        shift
      done
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      TARGETS+=("$1")
      ;;
  esac
  shift
done

if ((${#TARGETS[@]} == 0)); then
  usage >&2
  exit 2
fi

for command in ssh scp; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command is missing: $command" >&2
    exit 1
  }
done

for file in \
  10-block-lg-telemetry \
  20-block-lg-ips \
  30-enforce-lg-privacy \
  decline-tos.sh \
  clear-app-update-gate.sh \
  verify-lockout.sh
do
  test -f "$PAYLOAD_DIR/$file" || {
    echo "Payload is missing: $PAYLOAD_DIR/$file" >&2
    exit 1
  }
done

normalize_target() {
  case "$1" in
    *@*) printf '%s\n' "$1" ;;
    *)   printf 'root@%s\n' "$1" ;;
  esac
}

wait_for_reboot() {
  local target="$1"
  local attempt
  local went_down=0

  # Avoid mistaking the old SSH daemon for a completed reboot.
  for ((attempt = 1; attempt <= 20; attempt++)); do
    if ! ssh -o BatchMode=yes -o ConnectTimeout=3 "$target" true \
        >/dev/null 2>&1; then
      went_down=1
      break
    fi
    sleep 2
  done

  if ((went_down == 0)); then
    echo "Warning: $target was not observed going offline" >&2
  fi

  for ((attempt = 1; attempt <= 60; attempt++)); do
    if ssh -o BatchMode=yes -o ConnectTimeout=3 "$target" \
        'test -e /tmp/webosbrew_startup &&
         test ! -e /var/luna/preferences/webosbrew_failsafe' \
        >/dev/null 2>&1; then
      # Allow the privacy hook's delayed second pass to finish.
      sleep 35
      return 0
    fi
    sleep 5
  done

  echo "Timed out waiting for $target after reboot" >&2
  return 1
}

install_target() {
  local supplied_target="$1"
  local target
  target="$(normalize_target "$supplied_target")"

  echo
  echo "== Installing LG lockout on $target =="

  # Preflight deliberately makes no changes.
  ssh "${SSH_OPTIONS[@]}" "$target" '
    set -eu
    test "$(id -u)" -eq 0
    test -x /var/lib/webosbrew/startup.sh
    command -v python3 >/dev/null
    command -v findmnt >/dev/null
    command -v ip >/dev/null
    test -f /var/luna/preferences/eula
    test -f /var/luna/preferences/option
    test -f /var/luna/preferences/general
  '

  # Back up target-specific settings and any previously installed scripts.
  ssh "${SSH_OPTIONS[@]}" "$target" 'sh -s' <<'REMOTE_BACKUP'
set -eu
timestamp=$(date +%Y%m%d%H%M%S)
backup="/tmp/lg-lockout-backup.$timestamp"
mkdir -p "$backup/preferences" "$backup/init.d" "$backup/lg-lockout"

for file in \
  /etc/hosts \
  /var/luna/preferences/eula \
  /var/luna/preferences/option \
  /var/luna/preferences/general \
  /mnt/lg/cmn_data/sdp/sdx/server_addr_version.conf
do
  if [ -e "$file" ]; then
    cp -a "$file" "$backup/preferences/"
  fi
done

for file in \
  /var/lib/webosbrew/init.d/10-block-lg-telemetry \
  /var/lib/webosbrew/init.d/20-block-lg-ips \
  /var/lib/webosbrew/init.d/30-enforce-lg-privacy
do
  if [ -e "$file" ]; then
    cp -a "$file" "$backup/init.d/"
  fi
done

for file in \
  /var/lib/webosbrew/lg-lockout/decline-tos.sh \
  /var/lib/webosbrew/lg-lockout/clear-app-update-gate.sh \
  /var/lib/webosbrew/lg-lockout/verify-lockout.sh
do
  if [ -e "$file" ]; then
    cp -a "$file" "$backup/lg-lockout/"
  fi
done

mkdir -p /var/lib/webosbrew/init.d /var/lib/webosbrew/lg-lockout
echo "Backup: $backup"
REMOTE_BACKUP

  scp "${SSH_OPTIONS[@]}" -p \
    "$PAYLOAD_DIR/10-block-lg-telemetry" \
    "$PAYLOAD_DIR/20-block-lg-ips" \
    "$PAYLOAD_DIR/30-enforce-lg-privacy" \
    "$target:/var/lib/webosbrew/init.d/"

  scp "${SSH_OPTIONS[@]}" -p \
    "$PAYLOAD_DIR/decline-tos.sh" \
    "$PAYLOAD_DIR/clear-app-update-gate.sh" \
    "$PAYLOAD_DIR/verify-lockout.sh" \
    "$target:/var/lib/webosbrew/lg-lockout/"

  ssh "${SSH_OPTIONS[@]}" "$target" '
    set -eu
    chmod 755 \
      /var/lib/webosbrew/init.d/10-block-lg-telemetry \
      /var/lib/webosbrew/init.d/20-block-lg-ips \
      /var/lib/webosbrew/init.d/30-enforce-lg-privacy \
      /var/lib/webosbrew/lg-lockout/decline-tos.sh \
      /var/lib/webosbrew/lg-lockout/clear-app-update-gate.sh \
      /var/lib/webosbrew/lg-lockout/verify-lockout.sh

    # Enable Homebrew Channel core OTA protection and strict extra blocking.
    touch /var/luna/preferences/webosbrew_block_updates
    rm -f /var/luna/preferences/webosbrew_block_updates_extra_off

    # Apply every layer immediately; init.d reapplies it on future boots.
    sh /var/lib/webosbrew/init.d/10-block-lg-telemetry
    sh /var/lib/webosbrew/init.d/20-block-lg-ips
    sh /var/lib/webosbrew/init.d/30-enforce-lg-privacy
  '

  if ((REBOOT)); then
    echo "Rebooting $target..."
    ssh "${SSH_OPTIONS[@]}" "$target" 'sync; reboot' || true
    wait_for_reboot "$target"
  fi

  ssh "${SSH_OPTIONS[@]}" "$target" \
    'sh /var/lib/webosbrew/lg-lockout/verify-lockout.sh'
}

for target in "${TARGETS[@]}"; do
  install_target "$target"
done

echo
echo "All requested TVs were installed and verified."
