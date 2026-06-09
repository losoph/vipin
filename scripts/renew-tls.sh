#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE="$ROOT_DIR/.env"
ACME_HOME="$ROOT_DIR/.acme.sh"
TLS_DIR="$ROOT_DIR/secrets/tls"
ACME_SH="$ACME_HOME/acme.sh"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing .env. Run: make init" >&2
  exit 1
fi

if [ ! -x "$ACME_SH" ]; then
  echo "acme.sh is not installed. Run: make tls" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

VIPIN_DOMAIN="${VIPIN_DOMAIN:-}"
if [ -z "$VIPIN_DOMAIN" ]; then
  echo "VIPIN_DOMAIN is not set in .env" >&2
  exit 1
fi

RELOAD_CMD="docker compose -f $ROOT_DIR/docker-compose.yml restart hysteria 2>/dev/null || true"

"$ACME_SH" --home "$ACME_HOME" --renew \
  -d "$VIPIN_DOMAIN" \
  --reloadcmd "$RELOAD_CMD"

if [ -f "$TLS_DIR/privkey.pem" ]; then
  chmod 600 "$TLS_DIR/privkey.pem"
fi

if [ -f "$TLS_DIR/fullchain.pem" ]; then
  chmod 644 "$TLS_DIR/fullchain.pem"
fi

echo "Certificate renewal finished for ${VIPIN_DOMAIN}."
