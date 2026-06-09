# Decisions

## Scope

This is a personal VPN setup for one owner and up to five trusted users. It is
not designed as a public VPN service.

## Base Projects

- Primary core: XTLS/Xray-core
- Secondary protocol: Hysteria2

The repo is a deployment wrapper around upstream images and configuration. It is
not intended to carry a large custom fork until a concrete upstream patch is
needed.

## Network Profile

- Xray uses `443/tcp` with VLESS, XTLS Vision, and REALITY.
- Hysteria2 uses `443/udp` with password auth, Salamander obfuscation, and HTTP
  masquerade.
- Both profiles can share the same domain and numeric port because TCP and UDP
  are separate sockets.

## Client Profile

The first client target is Happ. Hiddify, v2rayN, v2rayNG, Streisand, and other
Xray/Hysteria-capable clients are secondary compatibility targets.

## Operational Model

- Secrets live in `.env`, `secrets/`, and `generated/`.
- Upstream updates are monitored manually.
- Changelog is maintained manually.
- Panels are intentionally excluded for the first version to keep RAM usage,
  attack surface, and maintenance cost low.
- HTTPS fallback is served by Caddy on an internal Docker port; Xray forwards
  non-client traffic there on the same public `443/tcp` socket.
- TLS for Hysteria2 is issued with acme.sh via HTTP-01 on port `80/tcp`.
- Host firewall is applied with `scripts/harden-vps.sh` (ufw only; no fail2ban by
  default to save RAM).
- `scripts/guardrails.sh` validates secrets hygiene, TLS expiry, compose config,
  and container health before/after deploy.

