#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE="$ROOT_DIR/.env"
ACME_HOME="$ROOT_DIR/.acme.sh"
TLS_DIR="$ROOT_DIR/secrets/tls"
WEBROOT="$ROOT_DIR/static/acme"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing .env. Run: make init" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

VIPIN_DOMAIN="${VIPIN_DOMAIN:-}"
VIPIN_CONTACT_EMAIL="${VIPIN_CONTACT_EMAIL:-}"
ACME_PORT="${ACME_PORT:-80}"

if [ -z "$VIPIN_DOMAIN" ] || printf '%s' "$VIPIN_DOMAIN" | grep -qE 'example\.com$'; then
  echo "Set a real VIPIN_DOMAIN in .env before issuing TLS certificates." >&2
  exit 1
fi

if [ -z "$VIPIN_CONTACT_EMAIL" ] || printf '%s' "$VIPIN_CONTACT_EMAIL" | grep -q 'example.com'; then
  echo "Set VIPIN_CONTACT_EMAIL in .env for Let's Encrypt registration." >&2
  exit 1
fi

need curl
need openssl

mkdir -p "$WEBROOT" "$TLS_DIR" "$ACME_HOME"

if [ ! -x "$ACME_HOME/acme.sh" ]; then
  echo "Installing acme.sh into $ACME_HOME ..."
  LE_WORKING_DIR="$ACME_HOME" curl -fsS https://get.acme.sh | LE_WORKING_DIR="$ACME_HOME" sh -s "email=${VIPIN_CONTACT_EMAIL}"
fi

ACME_SH="$ACME_HOME/acme.sh"
if [ ! -x "$ACME_SH" ]; then
  echo "acme.sh installation failed." >&2
  exit 1
fi

if command -v docker >/dev/null 2>&1 && docker compose -f "$ROOT_DIR/docker-compose.yml" ps --status running --format '{{.Service}}' 2>/dev/null | grep -qx caddy; then
  echo "Caddy is running; using webroot mode on port ${ACME_PORT}."
else
  echo "Starting Caddy for ACME webroot (port ${ACME_PORT}) ..."
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is required to serve the ACME webroot." >&2
    exit 1
  fi
  "$ROOT_DIR/scripts/render-configs.sh"
  docker compose -f "$ROOT_DIR/docker-compose.yml" up -d caddy
fi

RELOAD_CMD="docker compose -f $ROOT_DIR/docker-compose.yml restart hysteria 2>/dev/null || true"

echo "Requesting certificate for ${VIPIN_DOMAIN} ..."
"$ACME_SH" --home "$ACME_HOME" --issue \
  -d "$VIPIN_DOMAIN" \
  -w "$WEBROOT" \
  --server letsencrypt

"$ACME_SH" --home "$ACME_HOME" --install-cert \
  -d "$VIPIN_DOMAIN" \
  --key-file "$TLS_DIR/privkey.pem" \
  --fullchain-file "$TLS_DIR/fullchain.pem" \
  --reloadcmd "$RELOAD_CMD"

chmod 600 "$TLS_DIR/privkey.pem"
chmod 644 "$TLS_DIR/fullchain.pem"

cat <<EOF

TLS certificate installed:
  secrets/tls/fullchain.pem
  secrets/tls/privkey.pem

Renewal: run ./scripts/renew-tls.sh (cron-friendly).
EOF
