#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE="$ROOT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing .env. Run: make init" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

required_vars="
VIPIN_DOMAIN
XRAY_PORT
XRAY_CLIENT_UUID
XRAY_REALITY_PRIVATE_KEY
XRAY_REALITY_PUBLIC_KEY
XRAY_REALITY_SHORT_ID
XRAY_REALITY_SERVER_NAME
XRAY_REALITY_DEST
HYSTERIA_PORT
HYSTERIA_PASSWORD
HYSTERIA_OBFS_PASSWORD
HYSTERIA_MASQUERADE_URL
HYSTERIA_INSECURE
"

FALLBACK_ADDR="${FALLBACK_ADDR:-caddy:8080}"

for name in $required_vars; do
  eval "value=\${$name:-}"
  if [ -z "$value" ] || printf '%s' "$value" | grep -q '^replace-with-'; then
    echo "Missing or placeholder value in .env: $name" >&2
    exit 1
  fi
done

mkdir -p \
  "$ROOT_DIR/configs/xray" \
  "$ROOT_DIR/configs/hysteria" \
  "$ROOT_DIR/configs/caddy" \
  "$ROOT_DIR/static/acme" \
  "$ROOT_DIR/generated"

cat >"$ROOT_DIR/configs/xray/config.json" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-reality",
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${XRAY_CLIENT_UUID}",
            "flow": "xtls-rprx-vision",
            "email": "vipin-primary"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${XRAY_REALITY_DEST}",
          "xver": 0,
          "serverNames": [
            "${XRAY_REALITY_SERVER_NAME}"
          ],
          "privateKey": "${XRAY_REALITY_PRIVATE_KEY}",
          "shortIds": [
            "${XRAY_REALITY_SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      },
      "fallbacks": [
        {
          "dest": "${FALLBACK_ADDR}",
          "xver": 0
        }
      ]
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

cat >"$ROOT_DIR/configs/hysteria/config.yaml" <<EOF
listen: :443

tls:
  cert: /etc/hysteria/tls/fullchain.pem
  key: /etc/hysteria/tls/privkey.pem

auth:
  type: password
  password: ${HYSTERIA_PASSWORD}

obfs:
  type: salamander
  salamander:
    password: ${HYSTERIA_OBFS_PASSWORD}

masquerade:
  type: proxy
  proxy:
    url: ${HYSTERIA_MASQUERADE_URL}
    rewriteHost: true
EOF

cat >"$ROOT_DIR/configs/caddy/Caddyfile" <<EOF
# Internal fallback for Xray REALITY probing (not exposed on the host).
:8080 {
    root * /srv/www
    file_server
    header -Server
    encode gzip
}

# ACME webroot and plain HTTP landing page on port 80.
:80 {
    handle /.well-known/acme-challenge/* {
        root * /srv/acme
        file_server
    }
    handle {
        root * /srv/www
        file_server
        header -Server
        encode gzip
    }
}
EOF

VLESS_LINK="vless://${XRAY_CLIENT_UUID}@${VIPIN_DOMAIN}:${XRAY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${XRAY_REALITY_SERVER_NAME}&fp=chrome&pbk=${XRAY_REALITY_PUBLIC_KEY}&sid=${XRAY_REALITY_SHORT_ID}&type=tcp&headerType=none#vipin-xray-reality"
HYSTERIA_LINK="hysteria2://${HYSTERIA_PASSWORD}@${VIPIN_DOMAIN}:${HYSTERIA_PORT}/?sni=${VIPIN_DOMAIN}&insecure=${HYSTERIA_INSECURE}&obfs=salamander&obfs-password=${HYSTERIA_OBFS_PASSWORD}#vipin-hysteria2"

cat >"$ROOT_DIR/generated/client-profiles.txt" <<EOF
vipin-xray-reality
${VLESS_LINK}

vipin-hysteria2
${HYSTERIA_LINK}
EOF

printf '%s\n%s\n' "$VLESS_LINK" "$HYSTERIA_LINK" >"$ROOT_DIR/generated/subscription.txt"
chmod 600 "$ROOT_DIR/generated/client-profiles.txt" "$ROOT_DIR/generated/subscription.txt"

echo "Rendered configs:"
echo "  configs/xray/config.json"
echo "  configs/hysteria/config.yaml"
echo "  configs/caddy/Caddyfile"
echo "  generated/client-profiles.txt"
echo "  generated/subscription.txt"

