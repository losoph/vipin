.PHONY: init render up down restart logs ps config check tls renew-tls guardrails harden status

init:
	./scripts/init-env.sh

render:
	./scripts/render-configs.sh

up: render
	docker compose up -d

down:
	docker compose down

restart: render
	docker compose up -d --force-recreate

logs:
	docker compose logs -f --tail=100

ps:
	docker compose ps

config:
	docker compose config

check:
	sh -n scripts/init-env.sh scripts/render-configs.sh scripts/dev-self-signed-cert.sh \
		scripts/issue-tls.sh scripts/renew-tls.sh scripts/guardrails.sh scripts/harden-vps.sh
	@if command -v docker >/dev/null 2>&1; then \
		docker compose config >/dev/null; \
	else \
		echo "docker not found; skipped docker compose config"; \
	fi

tls:
	./scripts/issue-tls.sh

renew-tls:
	./scripts/renew-tls.sh

guardrails:
	./scripts/guardrails.sh

status: guardrails ps

harden:
	@echo "Run on the VPS as root: sudo ./scripts/harden-vps.sh"
