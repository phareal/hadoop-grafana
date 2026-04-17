#!/bin/bash
set -e
echo "=== Démarrage cluster Groupe 6 ==="
docker-compose up -d
echo "Attente 35s pour l'initialisation JVM..."
sleep 35
cd "$(dirname "$0")/.."
./healthcheck.sh
