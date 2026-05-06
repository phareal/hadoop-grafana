# =============================================================================
# Makefile — Stack Big Data Groupe 6
# =============================================================================

SHELL := /usr/bin/env bash
COMPOSE := docker compose

# Sources surveillées pour régénération du payload de install.sh.
# Toute modif d'un de ces fichiers déclenche `make install.sh`.
TEMPLATE_SOURCES := \
	docker-compose.yml \
	healthcheck.sh \
	README.md \
	.gitignore \
	$(wildcard config/*.xml) \
	$(wildcard flume/*) \
	$(wildcard dashboard/*) \
	$(wildcard dashboard/public/*) \
	$(wildcard crud-app/*) \
	$(wildcard crud-app/public/*) \
	$(wildcard caddy/*) \
	$(wildcard grafana/dashboards/*) \
	$(wildcard grafana/provisioning/dashboards/*) \
	$(wildcard grafana/provisioning/datasources/*) \
	scripts/start.sh \
	scripts/stop.sh \
	scripts/test-hdfs.sh \
	scripts/fix-namenode.sh

.PHONY: help install scaffold check up down restart logs ps clean payload installer test

help:
	@echo "Cibles disponibles :"
	@echo "  make install     — exécute scripts/install.sh (full)"
	@echo "  make scaffold    — génère uniquement les fichiers (--scaffold)"
	@echo "  make check       — vérifie les prérequis (--check)"
	@echo "  make up          — démarre la stack (docker compose up -d)"
	@echo "  make down        — arrête la stack"
	@echo "  make restart     — down + up"
	@echo "  make ps          — état des conteneurs"
	@echo "  make logs S=svc  — suit les logs d'un service"
	@echo "  make test        — test HDFS"
	@echo "  make payload     — régénère le payload base64 dans install.sh"
	@echo "  make installer   — alias de payload"
	@echo "  make clean       — supprime data/ et arrête tout"

# -----------------------------------------------------------------------------
# Régénération automatique du payload self-extracting
# -----------------------------------------------------------------------------
# install.sh dépend de tous les fichiers du projet. Toute modification déclenche
# une régénération du tarball base64 embarqué. Évite payload stale vs fichiers.
scripts/install.sh: $(TEMPLATE_SOURCES) scripts/build-installer.sh
	@./scripts/build-installer.sh

payload installer: scripts/install.sh ## Force régénération du payload

# -----------------------------------------------------------------------------
# Cibles d'orchestration
# -----------------------------------------------------------------------------
install: scripts/install.sh
	@./scripts/install.sh

scaffold: scripts/install.sh
	@./scripts/install.sh --scaffold --force

check:
	@./scripts/install.sh --check

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

restart: down up

ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f $(S)

test:
	@./scripts/test-hdfs.sh

clean: down
	@rm -rf data/nameNode data/dataNode
	@echo "✓ Volumes locaux supprimés."
