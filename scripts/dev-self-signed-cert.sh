#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE="$ROOT_DIR/.env"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

VIPIN_DOMAIN="${VIPIN_DOMAIN:-localhost}"
TLS_DIR="$ROOT_DIR/secrets/tls"

mkdir -p "$TLS_DIR"

openssl req \
  -x509 \
  -nodes \
  -newkey rsa:2048 \
  -days 14 \
  -keyout "$TLS_DIR/privkey.pem" \
  -out "$TLS_DIR/fullchain.pem" \
  -subj "/CN=${VIPIN_DOMAIN}"

chmod 600 "$TLS_DIR/privkey.pem"
chmod 644 "$TLS_DIR/fullchain.pem"

cat <<EOF
Created a short-lived self-signed certificate for local smoke tests.
For production, replace these files with a real certificate:
  secrets/tls/fullchain.pem
  secrets/tls/privkey.pem
EOF

