#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE="$ROOT_DIR/.env"

rand_base64url() {
  bytes="${1:-24}"
  openssl rand -base64 "$bytes" | tr -d '\n' | tr '+/' '-_' | tr -d '='
}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

if [ -f "$ENV_FILE" ]; then
  echo ".env already exists; rendering configs from current values."
  exec "$ROOT_DIR/scripts/render-configs.sh"
fi

need openssl
need docker

VIPIN_DOMAIN="${VIPIN_DOMAIN:-vpn.example.com}"
VIPIN_CONTACT_EMAIL="${VIPIN_CONTACT_EMAIL:-admin@example.com}"
XRAY_IMAGE="${XRAY_IMAGE:-ghcr.io/xtls/xray-core}"
XRAY_IMAGE_TAG="${XRAY_IMAGE_TAG:-latest}"
HYSTERIA_IMAGE="${HYSTERIA_IMAGE:-tobyxdd/hysteria}"
HYSTERIA_IMAGE_TAG="${HYSTERIA_IMAGE_TAG:-latest}"
CADDY_IMAGE="${CADDY_IMAGE:-caddy}"
CADDY_IMAGE_TAG="${CADDY_IMAGE_TAG:-2-alpine}"
XRAY_PORT="${XRAY_PORT:-443}"
HYSTERIA_PORT="${HYSTERIA_PORT:-443}"
ACME_PORT="${ACME_PORT:-80}"
FALLBACK_ADDR="${FALLBACK_ADDR:-caddy:8080}"
XRAY_REALITY_SERVER_NAME="${XRAY_REALITY_SERVER_NAME:-www.cloudflare.com}"
XRAY_REALITY_DEST="${XRAY_REALITY_DEST:-www.cloudflare.com:443}"
HYSTERIA_MASQUERADE_URL="${HYSTERIA_MASQUERADE_URL:-https://www.cloudflare.com/}"
HYSTERIA_INSECURE="${HYSTERIA_INSECURE:-0}"

if command -v uuidgen >/dev/null 2>&1; then
  XRAY_CLIENT_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
else
  XRAY_CLIENT_UUID=$(openssl rand -hex 16 | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\)$/\1-\2-\3-\4-\5/')
fi

echo "Generating Xray REALITY keypair with Docker image ${XRAY_IMAGE}:${XRAY_IMAGE_TAG}..."
REALITY_KEYS=$(docker run --rm "${XRAY_IMAGE}:${XRAY_IMAGE_TAG}" x25519)
XRAY_REALITY_PRIVATE_KEY=$(printf '%s\n' "$REALITY_KEYS" | awk -F': ' '/Private key/ {print $2}')
XRAY_REALITY_PUBLIC_KEY=$(printf '%s\n' "$REALITY_KEYS" | awk -F': ' '/Public key/ {print $2}')

if [ -z "$XRAY_REALITY_PRIVATE_KEY" ] || [ -z "$XRAY_REALITY_PUBLIC_KEY" ]; then
  echo "Could not parse Xray REALITY keys. Raw output:" >&2
  printf '%s\n' "$REALITY_KEYS" >&2
  exit 1
fi

XRAY_REALITY_SHORT_ID=$(openssl rand -hex 8)
HYSTERIA_PASSWORD=$(rand_base64url 24)
HYSTERIA_OBFS_PASSWORD=$(rand_base64url 24)

cat >"$ENV_FILE" <<EOF
VIPIN_DOMAIN=${VIPIN_DOMAIN}
VIPIN_CONTACT_EMAIL=${VIPIN_CONTACT_EMAIL}

XRAY_IMAGE=${XRAY_IMAGE}
XRAY_IMAGE_TAG=${XRAY_IMAGE_TAG}
HYSTERIA_IMAGE=${HYSTERIA_IMAGE}
HYSTERIA_IMAGE_TAG=${HYSTERIA_IMAGE_TAG}
CADDY_IMAGE=${CADDY_IMAGE}
CADDY_IMAGE_TAG=${CADDY_IMAGE_TAG}

XRAY_PORT=${XRAY_PORT}
ACME_PORT=${ACME_PORT}
FALLBACK_ADDR=${FALLBACK_ADDR}
XRAY_CLIENT_UUID=${XRAY_CLIENT_UUID}
XRAY_REALITY_PRIVATE_KEY=${XRAY_REALITY_PRIVATE_KEY}
XRAY_REALITY_PUBLIC_KEY=${XRAY_REALITY_PUBLIC_KEY}
XRAY_REALITY_SHORT_ID=${XRAY_REALITY_SHORT_ID}
XRAY_REALITY_SERVER_NAME=${XRAY_REALITY_SERVER_NAME}
XRAY_REALITY_DEST=${XRAY_REALITY_DEST}

HYSTERIA_PORT=${HYSTERIA_PORT}
HYSTERIA_PASSWORD=${HYSTERIA_PASSWORD}
HYSTERIA_OBFS_PASSWORD=${HYSTERIA_OBFS_PASSWORD}
HYSTERIA_MASQUERADE_URL=${HYSTERIA_MASQUERADE_URL}
HYSTERIA_INSECURE=${HYSTERIA_INSECURE}
EOF

chmod 600 "$ENV_FILE"
"$ROOT_DIR/scripts/render-configs.sh"

cat <<EOF

Created .env, rendered server configs, and exported client profiles.
Next:
  1. Replace VIPIN_DOMAIN in .env with your real domain.
  2. Issue TLS certs: make tls  (or use ./scripts/dev-self-signed-cert.sh for local tests)
  3. Run: make up
EOF

