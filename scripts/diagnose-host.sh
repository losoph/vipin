#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE="$ROOT_DIR/.env"

note() {
  printf '%s\n' "$1"
}

section() {
  note ""
  note "=== $1 ==="
}

section "Host"
uname -a
if command -v hostname >/dev/null 2>&1; then
  note "hostname: $(hostname -f 2>/dev/null || hostname)"
fi

if [ -f "$ENV_FILE" ]; then
  section "vipin .env (public ports)"
  grep -E '^(VIPIN_DOMAIN|XRAY_PORT|HYSTERIA_PORT|ACME_PORT|MTPROTO_PORT|WG_PORT|VIPIN_EXTRA_)=' "$ENV_FILE" 2>/dev/null || true
fi

section "UFW status"
if command -v ufw >/dev/null 2>&1; then
  ufw status verbose 2>/dev/null || ufw status 2>/dev/null || note "ufw installed but status unavailable"
else
  note "ufw not installed"
fi

section "Listening ports"
if command -v ss >/dev/null 2>&1; then
  ss -tulpn 2>/dev/null | sed -n '1p;/LISTEN/p;/UNCONN/p' || ss -tulpn
else
  note "ss not found"
fi

section "Docker containers"
if command -v docker >/dev/null 2>&1; then
  docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || docker ps -a
else
  note "docker not found"
fi

section "WireGuard"
if ip link show wg0 >/dev/null 2>&1; then
  ip -brief addr show wg0
  if command -v wg >/dev/null 2>&1; then
    wg show wg0 2>/dev/null || true
  fi
else
  note "wg0 interface not found"
fi

section "MTProto / related processes"
if command -v pgrep >/dev/null 2>&1; then
  pgrep -af 'mtprotoproxy|mtproto' 2>/dev/null || note "no mtprotoproxy process found"
else
  ps aux 2>/dev/null | grep -E '[m]tprotoproxy|[m]tproto' || note "no mtprotoproxy process found"
fi

section "Suggested firewall openings"
SSH_PORT="${VIPIN_SSH_PORT:-22}"
ACME_PORT="${ACME_PORT:-80}"
XRAY_PORT="${XRAY_PORT:-443}"
HYSTERIA_PORT="${HYSTERIA_PORT:-443}"
MTPROTO_PORT="${MTPROTO_PORT:-}"
WG_PORT="${WG_PORT:-51820}"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

note "vipin:"
note "  ${SSH_PORT}/tcp  ssh"
note "  ${ACME_PORT}/tcp  acme"
note "  ${XRAY_PORT}/tcp  xray"
note "  ${HYSTERIA_PORT}/udp  hysteria"

if [ -n "${MTPROTO_PORT:-}" ]; then
  note "mtproto:"
  note "  ${MTPROTO_PORT}/tcp  mtproto (from .env)"
elif ss -tulpn 2>/dev/null | grep -q 'mtprotoproxy'; then
  ss -tulpn 2>/dev/null | grep 'mtprotoproxy' | sed 's/^/  /' || true
else
  note "mtproto:"
  note "  set MTPROTO_PORT in .env if mtproto uses a dedicated TCP port"
fi

if ip link show wg0 >/dev/null 2>&1; then
  if ss -ulpn 2>/dev/null | grep -qE ':(51820|wg)'; then
    ss -ulpn 2>/dev/null | grep -E '51820|wg' | sed 's/^/  /' || true
  fi
  note "wireguard:"
  note "  ${WG_PORT}/udp  wireguard (default, adjust WG_PORT in .env if different)"
else
  note "wireguard: wg0 not detected"
fi

note ""
note "To apply missing UFW rules without wiping existing ones:"
note "  sudo ./scripts/ufw-sync.sh"
