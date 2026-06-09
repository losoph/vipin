#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE="$ROOT_DIR/.env"

SSH_PORT="${VIPIN_SSH_PORT:-22}"
ACME_PORT="${ACME_PORT:-80}"
XRAY_PORT="${XRAY_PORT:-443}"
HYSTERIA_PORT="${HYSTERIA_PORT:-443}"
MTPROTO_PORT="${MTPROTO_PORT:-}"
WG_PORT="${WG_PORT:-51820}"
VIPIN_EXTRA_TCP_PORTS="${VIPIN_EXTRA_TCP_PORTS:-}"
VIPIN_EXTRA_UDP_PORTS="${VIPIN_EXTRA_UDP_PORTS:-}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Add or refresh UFW rules for vipin and co-resident services.

Unlike harden-vps.sh, this script does NOT run "ufw reset".
It only ensures the configured ports are allowed.

Configure in .env:
  MTPROTO_PORT=8443          # mtproto TCP port, if used
  WG_PORT=51820              # wireguard UDP port
  VIPIN_EXTRA_TCP_PORTS=     # comma-separated, e.g. 5222,8443
  VIPIN_EXTRA_UDP_PORTS=     # comma-separated extras

Usage:
  sudo ./scripts/ufw-sync.sh [--dry-run]
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo ./scripts/ufw-sync.sh" >&2
  exit 1
fi

if ! command -v ufw >/dev/null 2>&1; then
  echo "ufw is required. Install with: apt-get install -y ufw" >&2
  exit 1
fi

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+ %s\n' "$*"
  else
    "$@"
  fi
}

allow_tcp() {
  port="$1"
  comment="$2"
  [ -n "$port" ] || return 0
  run ufw allow "${port}/tcp" comment "$comment"
}

allow_udp() {
  port="$1"
  comment="$2"
  [ -n "$port" ] || return 0
  run ufw allow "${port}/udp" comment "$comment"
}

allow_tcp_list() {
  list="$1"
  comment="$2"
  [ -n "$list" ] || return 0
  # shellcheck disable=SC2086
  set -- $(printf '%s' "$list" | tr ',' ' ')
  for port in "$@"; do
    allow_tcp "$port" "$comment"
  done
}

allow_udp_list() {
  list="$1"
  comment="$2"
  [ -n "$list" ] || return 0
  # shellcheck disable=SC2086
  set -- $(printf '%s' "$list" | tr ',' ' ')
  for port in "$@"; do
    allow_udp "$port" "$comment"
  done
}

cat <<EOF
vipin ufw sync
============
EOF

if [ "$DRY_RUN" -eq 1 ]; then
  echo "(dry run)"
fi

run ufw default deny incoming
run ufw default allow outgoing
allow_tcp "$SSH_PORT" 'vipin ssh'
allow_tcp "$ACME_PORT" 'vipin acme'
allow_tcp "$XRAY_PORT" 'vipin xray'
allow_udp "$HYSTERIA_PORT" 'vipin hysteria'
allow_tcp "$MTPROTO_PORT" 'mtproto'
allow_udp "$WG_PORT" 'wireguard'
allow_tcp_list "$VIPIN_EXTRA_TCP_PORTS" 'extra tcp'
allow_udp_list "$VIPIN_EXTRA_UDP_PORTS" 'extra udp'

if [ "$DRY_RUN" -eq 0 ]; then
  ufw --force enable
  ufw status verbose
fi

cat <<EOF

Done. Existing unrelated UFW rules were preserved.

If MTProto uses host networking, set MTPROTO_PORT in .env to the real TCP port.
Default WireGuard port is ${WG_PORT}/udp unless overridden.
EOF
