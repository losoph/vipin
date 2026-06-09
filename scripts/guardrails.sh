#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE="$ROOT_DIR/.env"
TLS_CERT="$ROOT_DIR/secrets/tls/fullchain.pem"
TLS_KEY="$ROOT_DIR/secrets/tls/privkey.pem"
WARN_DAYS="${VIPIN_TLS_WARN_DAYS:-14}"

fail=0
warn=0

note() {
  printf '%s\n' "$1"
}

ok() {
  note "OK  $1"
}

bad() {
  note "ERR $1"
  fail=1
}

caution() {
  note "WARN $1"
  warn=1
}

check_env_file() {
  if [ ! -f "$ENV_FILE" ]; then
    bad ".env is missing (run: make init)"
    return
  fi

  if [ "$(stat -f '%OLp' "$ENV_FILE" 2>/dev/null || stat -c '%a' "$ENV_FILE")" != "600" ]; then
    caution ".env permissions should be 600"
  else
    ok ".env permissions are 600"
  fi

  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a

  for name in VIPIN_DOMAIN XRAY_CLIENT_UUID HYSTERIA_PASSWORD; do
    eval "value=\${$name:-}"
    if [ -z "$value" ] || printf '%s' "$value" | grep -q '^replace-with-'; then
      bad ".env placeholder or empty value: $name"
    fi
  done

  if printf '%s' "${VIPIN_DOMAIN:-}" | grep -qE 'example\.com$'; then
    caution "VIPIN_DOMAIN still looks like a placeholder"
  else
    ok "VIPIN_DOMAIN is set"
  fi
}

check_git_secrets() {
  if ! command -v git >/dev/null 2>&1; then
    caution "git not found; skipped secret-in-index check"
    return
  fi

  if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    caution "not a git repository; skipped secret-in-index check"
    return
  fi

  tracked=$(
    git -C "$ROOT_DIR" ls-files --cached 2>/dev/null | grep -E '(^|/)\.env$|secrets/|generated/' || true
  )
  if [ -n "$tracked" ]; then
    bad "sensitive paths are tracked by git:"
    printf '%s\n' "$tracked" | sed 's/^/      /'
  else
    ok "no sensitive paths tracked by git"
  fi
}

check_tls() {
  if [ ! -f "$TLS_CERT" ] || [ ! -f "$TLS_KEY" ]; then
    bad "Hysteria TLS files are missing (run: make tls)"
    return
  fi

  if [ "$(stat -f '%OLp' "$TLS_KEY" 2>/dev/null || stat -c '%a' "$TLS_KEY")" != "600" ]; then
    caution "privkey.pem permissions should be 600"
  else
    ok "TLS key permissions are 600"
  fi

  if ! command -v openssl >/dev/null 2>&1; then
    caution "openssl not found; skipped certificate expiry check"
    return
  fi

  enddate=$(openssl x509 -enddate -noout -in "$TLS_CERT" 2>/dev/null | cut -d= -f2)
  if [ -z "$enddate" ]; then
    bad "could not read TLS certificate expiry"
    return
  fi

  if end_epoch=$(date -j -f '%b %d %T %Y %Z' "$enddate" '+%s' 2>/dev/null); then
    :
  elif end_epoch=$(date -d "$enddate" '+%s' 2>/dev/null); then
    :
  else
    caution "could not parse certificate expiry date"
    return
  fi

  now_epoch=$(date '+%s')
  days_left=$(( (end_epoch - now_epoch) / 86400 ))

  if [ "$days_left" -lt 0 ]; then
    bad "TLS certificate expired"
  elif [ "$days_left" -lt "$WARN_DAYS" ]; then
    caution "TLS certificate expires in ${days_left} day(s)"
  else
    ok "TLS certificate valid for ${days_left} day(s)"
  fi
}

check_compose() {
  if ! command -v docker >/dev/null 2>&1; then
    caution "docker not found; skipped compose validation"
    return
  fi

  if docker compose -f "$ROOT_DIR/docker-compose.yml" config >/dev/null 2>&1; then
    ok "docker compose config is valid"
  else
    bad "docker compose config failed"
  fi
}

check_runtime() {
  if ! command -v docker >/dev/null 2>&1; then
    caution "docker not found; skipped runtime checks"
    return
  fi

  for svc in caddy xray hysteria; do
    cid=$(docker compose -f "$ROOT_DIR/docker-compose.yml" ps -q "$svc" 2>/dev/null || true)
    if [ -z "$cid" ]; then
      caution "service not running: $svc"
      continue
    fi

    health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid" 2>/dev/null || echo unknown)
    case "$health" in
      healthy) ok "service healthy: $svc" ;;
      none) caution "service has no healthcheck state: $svc" ;;
      *) bad "service health is $health: $svc" ;;
    esac
  done
}

note "vipin guardrails"
note "================"

check_env_file
check_git_secrets
check_tls
check_compose
check_runtime

note "================"
if [ "$fail" -ne 0 ]; then
  note "Result: FAILED"
  exit 1
fi

if [ "$warn" -ne 0 ]; then
  note "Result: PASSED WITH WARNINGS"
  exit 0
fi

note "Result: PASSED"
exit 0
