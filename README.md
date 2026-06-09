# vipin

Personal VPN server wrapper for a small private group.

The server exposes two independent profiles on one host:

- Xray: `VLESS + XTLS Vision + REALITY` on `443/tcp`
- Hysteria2: QUIC-based Hysteria2 with Salamander obfuscation on `443/udp`
- Caddy: lightweight HTTPS fallback for probing traffic and ACME webroot on `80/tcp`

The repository stores only non-sensitive deployment code. Runtime secrets live in
`.env`, `secrets/`, and `generated/`, which are ignored by git.

## Requirements

- Ubuntu VPS with 1 CPU, 1 GB RAM, 10 GB disk
- Docker and Docker Compose plugin
- A domain pointing to the VPS

## Quick Start

```sh
make init
```

Edit `.env` and set the real `VIPIN_DOMAIN` and `VIPIN_CONTACT_EMAIL`.

Issue a production TLS certificate for Hysteria2:

```sh
make tls
```

For a local smoke test only, use a temporary self-signed certificate instead:

```sh
./scripts/dev-self-signed-cert.sh
```

Start the stack:

```sh
make up
```

Check guardrails and service health:

```sh
make status
```

Client profiles are exported to:

- `generated/client-profiles.txt`
- `generated/subscription.txt`

## Production on VPS

1. Clone the repo and run `make init`.
2. Point DNS for your domain to the VPS.
3. Harden the host firewall:

```sh
sudo ./scripts/harden-vps.sh
```

4. Issue TLS certificates:

```sh
make tls
```

5. Start services:

```sh
make up
```

6. Add certificate renewal to cron (daily is enough for acme.sh):

```sh
0 3 * * * cd /path/to/vipin && ./scripts/renew-tls.sh >> /var/log/vipin-renew.log 2>&1
```

## Ports

| Port | Protocol | Service |
|------|----------|---------|
| 22 | tcp | SSH (adjust with `VIPIN_SSH_PORT`) |
| 80 | tcp | ACME challenges + plain HTTP landing page |
| 443 | tcp | Xray REALITY |
| 443 | udp | Hysteria2 |

## Resource Budget

Designed for a 1 GB VPS. Typical memory limits:

- Caddy fallback: 64 MB
- Xray: 256 MB
- Hysteria2: 128 MB

No panel, no extra observability stack.

## Security Notes

- Do not commit `.env`, TLS keys, or generated profiles.
- `make guardrails` checks permissions, TLS expiry, git hygiene, and container health.
- Hysteria requires a real certificate in production. Self-signed certs need
  `HYSTERIA_INSECURE=1` in clients and are only for local tests.
- Xray REALITY probing traffic is forwarded to Caddy on an internal Docker port,
  not exposed on the host.
