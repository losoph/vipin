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
Apply a minimal host firewall for vipin on Ubuntu.

Usage:
  ./scripts/harden-vps.sh [--dry-run]

Opens:
  - SSH (VIPIN_SSH_PORT, default 22)
  - ACME HTTP (ACME_PORT, default 80)
  - Xray REALITY (XRAY_PORT/tcp, default 443)
  - Hysteria2 (HYSTERIA_PORT/udp, default 443)
  - MTProto (MTPROTO_PORT/tcp, optional)
  - WireGuard (WG_PORT/udp, default 51820)
  - VIPIN_EXTRA_TCP_PORTS / VIPIN_EXTRA_UDP_PORTS (optional)

To add ports without wiping existing UFW rules, use scripts/ufw-sync.sh instead.
Environment overrides can come from .env.
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
  SSH_PORT="${VIPIN_SSH_PORT:-$SSH_PORT}"
  ACME_PORT="${ACME_PORT:-80}"
  XRAY_PORT="${XRAY_PORT:-443}"
  HYSTERIA_PORT="${HYSTERIA_PORT:-443}"
  MTPROTO_PORT="${MTPROTO_PORT:-}"
  WG_PORT="${WG_PORT:-51820}"
  VIPIN_EXTRA_TCP_PORTS="${VIPIN_EXTRA_TCP_PORTS:-}"
  VIPIN_EXTRA_UDP_PORTS="${VIPIN_EXTRA_UDP_PORTS:-}"
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root on the VPS: sudo ./scripts/harden-vps.sh" >&2
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

cat <<EOF
vipin host hardening
===================
SSH:      ${SSH_PORT}/tcp
ACME:     ${ACME_PORT}/tcp
Xray:     ${XRAY_PORT}/tcp
Hysteria: ${HYSTERIA_PORT}/udp
MTProto:  ${MTPROTO_PORT:-disabled}/tcp
WireGuard:${WG_PORT}/udp
Extras:   tcp=${VIPIN_EXTRA_TCP_PORTS:-none} udp=${VIPIN_EXTRA_UDP_PORTS:-none}
EOF

if [ "$DRY_RUN" -eq 1 ]; then
  echo "(dry run — no changes applied)"
fi

run ufw --force reset
run ufw default deny incoming
run ufw default allow outgoing
run ufw allow "${SSH_PORT}/tcp" comment 'vipin ssh'
run ufw allow "${ACME_PORT}/tcp" comment 'vipin acme'
run ufw allow "${XRAY_PORT}/tcp" comment 'vipin xray'
run ufw allow "${HYSTERIA_PORT}/udp" comment 'vipin hysteria'
if [ -n "$MTPROTO_PORT" ]; then
  run ufw allow "${MTPROTO_PORT}/tcp" comment 'mtproto'
fi
run ufw allow "${WG_PORT}/udp" comment 'wireguard'
if [ -n "$VIPIN_EXTRA_TCP_PORTS" ]; then
  # shellcheck disable=SC2086
  set -- $(printf '%s' "$VIPIN_EXTRA_TCP_PORTS" | tr ',' ' ')
  for port in "$@"; do
    run ufw allow "${port}/tcp" comment 'extra tcp'
  done
fi
if [ -n "$VIPIN_EXTRA_UDP_PORTS" ]; then
  # shellcheck disable=SC2086
  set -- $(printf '%s' "$VIPIN_EXTRA_UDP_PORTS" | tr ',' ' ')
  for port in "$@"; do
    run ufw allow "${port}/udp" comment 'extra udp'
  done
fi
run ufw --force enable

if [ "$DRY_RUN" -eq 0 ]; then
  ufw status verbose
  cat <<'EOF'

Firewall enabled.

Optional next steps (not installed automatically to save RAM):
  - fail2ban for SSH brute-force protection
  - unattended-upgrades for security patches

Verify SSH access in a second session before closing this one.
EOF
fi
