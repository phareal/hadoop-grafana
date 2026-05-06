#!/usr/bin/env bash
# =============================================================================
# install.sh — Installation complète du projet Big Data (Groupe 6)
# -----------------------------------------------------------------------------
# Décrit et exécute toutes les étapes nécessaires pour déployer la stack :
#   Docker → Docker Compose → Hadoop (HDFS + YARN) → Flume → Dashboard → Grafana
#
# Usage :
#   ./scripts/install.sh           # exécution complète
#   ./scripts/install.sh --dry-run # affiche les étapes sans rien exécuter
#   ./scripts/install.sh --check   # vérifie seulement les prérequis
# =============================================================================

set -euo pipefail

# Chemin absolu du script lui-même (résiste aux 'cd' ultérieurs).
# BASH_SOURCE[0] est plus fiable que $0 pour ça.
SELF_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ---------- Helpers install Docker ------------------------------------------
install_docker_linux() {
  info "Installation Docker via script officiel get.docker.com"
  info "Nécessite sudo. Ctrl-C pour annuler."
  $DRY_RUN && { echo "  [dry-run] curl -fsSL https://get.docker.com | sudo sh"; return 0; }
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sudo sh /tmp/get-docker.sh
  rm -f /tmp/get-docker.sh
  sudo usermod -aG docker "$USER" || true
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable --now docker
  fi
  # Activer groupe docker dans session courante sans re-login
  if ! groups | grep -qw docker; then
    warn "Groupe 'docker' pas encore actif dans cette session."
    info "Réexécution du script via 'newgrp docker' pour activer le groupe..."
    if ! $DRY_RUN; then
      exec newgrp docker <<EOF
exec "$0" $ORIG_ARGS
EOF
    fi
  fi
}

install_docker_macos() {
  if ! command -v brew >/dev/null 2>&1; then
    fail "Homebrew requis pour install auto sur macOS."
    info "Install Homebrew :"
    info '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    info "Puis relancer ce script."
    return 1
  fi
  info "Installation Docker Desktop via Homebrew"
  $DRY_RUN && { echo "  [dry-run] brew install --cask docker"; return 0; }
  brew install --cask docker
  info "Démarrage Docker Desktop..."
  open -a Docker
  info "Attente du démon Docker (max 90s)..."
  for i in $(seq 1 18); do
    sleep 5
    if docker info >/dev/null 2>&1; then
      ok "Docker Desktop prêt."
      return 0
    fi
    echo -n "."
  done
  warn "Docker Desktop pas encore prêt — terminer manuellement puis relancer le script."
  return 1
}

install_docker_windows() {
  fail "Install auto Docker Desktop non supportée sous Windows par ce script."
  info "Télécharger : https://www.docker.com/products/docker-desktop/"
  info "Puis relancer ce script depuis Git Bash / WSL."
  return 1
}

install_docker() {
  case "$PLATFORM" in
    linux)   install_docker_linux ;;
    macos)   install_docker_macos ;;
    windows) install_docker_windows ;;
  esac
}

# ---------- Couleurs ---------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

step()    { echo -e "\n${BOLD}${BLUE}==> [Étape $1]${NC} ${BOLD}$2${NC}"; }
info()    { echo -e "  ${CYAN}ℹ${NC}  $*"; }
ok()      { echo -e "  ${GREEN}✓${NC}  $*"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $*"; }
fail()    { echo -e "  ${RED}✗${NC}  $*" >&2; }
run()     { if $DRY_RUN; then echo -e "  ${YELLOW}[dry-run]${NC} $*"; else eval "$@"; fi; }

# ---------- Args -------------------------------------------------------------
DRY_RUN=false
CHECK_ONLY=false
SCAFFOLD_ONLY=false
FORCE=false
NO_SCAFFOLD=false
ORIG_ARGS="$*"
for arg in "$@"; do
  case "$arg" in
    --dry-run)     DRY_RUN=true ;;
    --check)       CHECK_ONLY=true ;;
    --scaffold)    SCAFFOLD_ONLY=true ;;
    --force)       FORCE=true ;;
    --no-scaffold) NO_SCAFFOLD=true ;;
    -h|--help)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
      cat <<EOF

Options :
  --dry-run       affiche les actions sans les exécuter
  --check         vérifie seulement les prérequis
  --scaffold      génère uniquement les fichiers du projet (pas de démarrage)
  --force         écrase les fichiers existants pendant le scaffold
  --no-scaffold   saute la génération de fichiers
EOF
      exit 0 ;;
    *) fail "Argument inconnu : $arg"; exit 1 ;;
  esac
done

# ---------- Scaffolding (templating) ----------------------------------------
# Tarball gzip+base64 embarqué en fin de script (après __PROJECT_TEMPLATE__).
# Régénération : tar --exclude=... -czf - . | base64 | fold -w 76
extract_payload() {
  awk '/^__PROJECT_TEMPLATE__$/{flag=1; next} flag' "$SELF_PATH"
}

scaffold_project() {
  local target="$1"
  local tmp tarball
  tmp="$(mktemp -d)"
  tarball="$tmp/project.tar.gz"
  extract_payload | base64 -d > "$tarball" 2>/dev/null \
    || { fail "Décodage payload échoué."; rm -rf "$tmp"; return 1; }

  if [ ! -s "$tarball" ]; then
    fail "Payload vide — script corrompu ou non régénéré."
    rm -rf "$tmp"; return 1
  fi

  info "Payload extrait : $(wc -c < "$tarball" | tr -d ' ') octets"

  # Liste des fichiers contenus
  local count
  count=$(tar -tzf "$tarball" 2>/dev/null | wc -l | tr -d ' ')
  info "$count fichiers à matérialiser dans $target"

  # Conflits ?
  local conflicts=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -e "$target/$f" ] && conflicts=$((conflicts+1))
  done < <(tar -tzf "$tarball" 2>/dev/null | grep -v '/$')

  if [ "$conflicts" -gt 0 ] && ! $FORCE; then
    warn "$conflicts fichier(s) existe(nt) déjà dans $target"
    if ! $DRY_RUN; then
      read -r -p "  Écraser ? [y/N] " ans
      [[ "$ans" =~ ^[Yy]$ ]] || { info "Conservation des fichiers existants — extraction annulée."; rm -rf "$tmp"; return 0; }
    fi
  fi

  if $DRY_RUN; then
    echo "  [dry-run] tar -xzf <payload> -C $target"
  else
    # Pré-vérif : détecter sous-dossiers root-owned bloquants
    local bad_dirs=""
    for d in scripts dashboard crud-app flume grafana caddy config; do
      if [ -d "$target/$d" ] && [ ! -w "$target/$d" ]; then
        bad_dirs="$bad_dirs $d"
      fi
    done
    if [ -n "$bad_dirs" ]; then
      fail "Dossiers non-writables (probablement créés par Docker en root) :$bad_dirs"
      info "Corriger avec :  sudo chown -R \$USER:\$(id -gn) $target"
      info "Puis relancer le script."
      rm -rf "$tmp"; return 1
    fi

    # Extraction : ignorer perms/owner du tarball, COPYFILE_DISABLE coupe ._* macOS
    if ! COPYFILE_DISABLE=1 tar --no-same-owner --no-same-permissions \
            -xzf "$tarball" -C "$target" 2>"$tmp/tar.err"; then
      fail "Extraction tar échouée."
      cat "$tmp/tar.err" >&2
      rm -rf "$tmp"; return 1
    fi
    if [ -s "$tmp/tar.err" ] && grep -qv 'Ignoring unknown extended header' "$tmp/tar.err"; then
      warn "Avertissements tar (non bloquants) :"
      grep -v 'Ignoring unknown extended header' "$tmp/tar.err" | head -5 >&2 || true
    fi

    chmod +x "$target"/healthcheck.sh "$target"/scripts/*.sh 2>/dev/null || true
    ok "Fichiers générés dans $target"
  fi
  rm -rf "$tmp"
}

# ---------- Localisation projet ---------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Si install.sh est dans scripts/, PROJECT_DIR = parent.
# Sinon (script copié dans dossier vide pour bootstrap), PROJECT_DIR = dossier courant.
if [ "$(basename "$SCRIPT_DIR")" = "scripts" ]; then
  PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  PROJECT_DIR="$SCRIPT_DIR"
fi
cd "$PROJECT_DIR"

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Installation Stack Big Data — Hadoop + Flume + Dashboard    ║"
echo "║  Groupe 6                                                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
info "Projet : $PROJECT_DIR"
$DRY_RUN && warn "Mode dry-run : aucune commande ne sera exécutée."

# =============================================================================
# Étape 0 — Génération des fichiers (templating)
# =============================================================================
if ! $NO_SCAFFOLD; then
  step 0 "Génération des fichiers du projet"
  info "Sources embarquées : docker-compose.yml, configs Hadoop, Dockerfiles, scripts, etc."
  scaffold_project "$PROJECT_DIR"
fi

if $SCAFFOLD_ONLY; then
  echo -e "\n${GREEN}${BOLD}✓ Scaffold terminé (mode --scaffold).${NC}"
  exit 0
fi

# =============================================================================
# Étape 1 — Détection de l'OS
# =============================================================================
step 1 "Détection système d'exploitation"
OS="$(uname -s)"
ARCH="$(uname -m)"
info "OS=$OS  Arch=$ARCH"

case "$OS" in
  Darwin)  PLATFORM="macos" ;;
  Linux)   PLATFORM="linux" ;;
  MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
  *) fail "OS non supporté : $OS"; exit 1 ;;
esac
ok "Plateforme détectée : $PLATFORM"

# =============================================================================
# Étape 2 — Vérification Docker
# =============================================================================
step 2 "Vérification / installation de Docker"
if ! command -v docker >/dev/null 2>&1; then
  warn "Docker non installé — tentative d'installation automatique."
  if ! $DRY_RUN; then
    read -r -p "  Installer Docker maintenant ? (sudo requis sur Linux) [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { fail "Installation annulée."; exit 1; }
  fi
  install_docker || { fail "Échec installation Docker."; exit 1; }
  if ! command -v docker >/dev/null 2>&1; then
    fail "Docker toujours absent du PATH après installation."
    info "Ouvrir un nouveau terminal puis relancer ce script."
    exit 1
  fi
fi
ok "docker présent : $(docker --version 2>/dev/null || echo 'version indisponible')"

# Tentatives de démarrage du démon Docker selon environnement Linux
start_docker_linux() {
  local methods_tried=""

  # 1. systemd standard
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    info "→ systemctl (systemd détecté)"
    methods_tried="$methods_tried systemctl"
    sudo systemctl unmask docker 2>/dev/null || true
    if sudo systemctl enable --now docker 2>/dev/null; then
      sleep 3
      docker info >/dev/null 2>&1 && return 0
    fi
  fi

  # 2. Snap (Ubuntu Core, certaines distros)
  if command -v snap >/dev/null 2>&1 && snap list docker >/dev/null 2>&1; then
    info "→ snap start docker"
    methods_tried="$methods_tried snap"
    sudo snap start docker 2>/dev/null || true
    sleep 3
    docker info >/dev/null 2>&1 && return 0
  fi

  # 3. service (SysV / OpenRC / Alpine)
  if command -v service >/dev/null 2>&1; then
    info "→ service docker start"
    methods_tried="$methods_tried service"
    sudo service docker start 2>/dev/null || true
    sleep 3
    docker info >/dev/null 2>&1 && return 0
  fi

  # 4. rootless (user-mode systemd)
  if [ -S "/run/user/$(id -u)/docker.sock" ] || \
     ([ -n "${XDG_RUNTIME_DIR:-}" ] && command -v systemctl >/dev/null 2>&1); then
    info "→ systemctl --user (rootless)"
    methods_tried="$methods_tried rootless"
    systemctl --user start docker 2>/dev/null || true
    export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"
    sleep 3
    docker info >/dev/null 2>&1 && return 0
  fi

  fail "Aucune méthode de démarrage n'a fonctionné. Essayées :$methods_tried"
  return 1
}

# Démon en cours d'exécution ?
if ! docker info >/dev/null 2>&1; then
  warn "Démon Docker pas démarré — tentative de démarrage."
  case "$PLATFORM" in
    macos)
      $DRY_RUN || open -a Docker || true
      info "Attente démarrage Docker Desktop (max 60s)..."
      for i in $(seq 1 12); do
        $DRY_RUN && break
        sleep 5
        docker info >/dev/null 2>&1 && break
      done
      ;;
    linux)
      if ! $DRY_RUN; then
        start_docker_linux || true
      fi
      ;;
  esac
  if ! $DRY_RUN && ! docker info >/dev/null 2>&1; then
    fail "Démon Docker injoignable."
    info "Diagnostic suggéré :"
    info "  sudo systemctl status docker"
    info "  sudo journalctl -u docker -n 50"
    info "  ps -p 1 -o comm=    # pour vérifier systemd vs autre init"
    info ""
    info "Cas WSL2 : démarrer Docker Desktop côté Windows, pas dans WSL."
    info "Cas Alpine/sans systemd :  sudo rc-service docker start"
    info "Cas rootless :  dockerd-rootless-setuptool.sh install"
    exit 1
  fi
fi
ok "Démon Docker actif."

# =============================================================================
# Étape 3 — Vérification Docker Compose
# =============================================================================
step 3 "Vérification / installation de Docker Compose"
if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
  ok "Plugin Compose v2 : $(docker compose version --short)"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
  ok "Binaire legacy : $(docker-compose --version)"
else
  warn "docker compose introuvable — tentative d'installation."
  case "$PLATFORM" in
    linux)
      if command -v apt-get >/dev/null 2>&1; then
        run "sudo apt-get update -y && sudo apt-get install -y docker-compose-plugin"
      elif command -v dnf >/dev/null 2>&1; then
        run "sudo dnf install -y docker-compose-plugin"
      elif command -v yum >/dev/null 2>&1; then
        run "sudo yum install -y docker-compose-plugin"
      else
        fail "Gestionnaire de paquets non détecté. Installer manuellement docker-compose-plugin."
        exit 1
      fi
      ;;
    macos|windows)
      fail "Compose absent — réinstaller Docker Desktop (Compose inclus)."
      exit 1
      ;;
  esac
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    ok "Plugin Compose installé : $(docker compose version --short)"
  else
    fail "Installation Compose échouée."
    exit 1
  fi
fi

# =============================================================================
# Étape 4 — Ressources système
# =============================================================================
step 4 "Vérification mémoire & disque"
TOTAL_RAM_GB=0
case "$PLATFORM" in
  macos) TOTAL_RAM_GB=$(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024)) ;;
  linux) TOTAL_RAM_GB=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo) ;;
esac
info "RAM totale : ${TOTAL_RAM_GB} Go"
[ "$TOTAL_RAM_GB" -lt 4 ] && warn "Recommandé : ≥ 4 Go RAM allouée à Docker."
DISK_FREE=$(df -h "$PROJECT_DIR" | awk 'NR==2 {print $4}')
info "Espace disque libre : $DISK_FREE"

# =============================================================================
# Étape 5 — Vérification ports
# =============================================================================
step 5 "Vérification des ports requis"
PORTS=(80 3000 4000 5000 8088 9000 9870 44444)
PORT_BUSY=0
for p in "${PORTS[@]}"; do
  if lsof -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
    warn "Port $p déjà occupé."
    PORT_BUSY=$((PORT_BUSY+1))
  fi
done
[ "$PORT_BUSY" -eq 0 ] && ok "Tous les ports sont libres."

if $CHECK_ONLY; then
  echo -e "\n${GREEN}${BOLD}✓ Vérifications terminées (mode --check).${NC}"
  exit 0
fi

# =============================================================================
# Étape 6 — Préparation des répertoires de données
# =============================================================================
step 6 "Préparation des volumes locaux"
info "Hadoop persiste NameNode/DataNode dans ./data/"
run "mkdir -p data/nameNode data/dataNode"
run "chmod -R 755 data/"
ok "Répertoires data/ prêts."

# =============================================================================
# Étape 7 — Pull des images Docker
# =============================================================================
step 7 "Téléchargement des images Docker de base"
info "Images : apache/hadoop:3, grafana/grafana, caddy:alpine"
info "(Apple Silicon : apache/hadoop:3 tourne en amd64 via Rosetta)"
run "docker pull apache/hadoop:3"
run "docker pull grafana/grafana:latest"
run "docker pull caddy:alpine"
ok "Images de base téléchargées."

# =============================================================================
# Étape 8 — Build des images custom
# =============================================================================
step 8 "Build des images applicatives"
info "Flume       → ./flume/Dockerfile      (agent collecteur de logs)"
info "Dashboard   → ./dashboard/Dockerfile  (Node.js console temps réel)"
info "CRUD-app    → ./crud-app/Dockerfile   (Node.js CRUD étudiants)"
run "$COMPOSE_CMD build flume dashboard crud-app"
ok "Images applicatives construites."

# =============================================================================
# Étape 9 — Démarrage du cluster Hadoop (HDFS)
# =============================================================================
step 9 "Démarrage HDFS — NameNode + DataNode"
info "NameNode : métadonnées + UI web (http://localhost:9870)"
info "DataNode : stockage des blocs"
run "$COMPOSE_CMD up -d namenode datanode"
info "Attente initialisation JVM (25s)..."
$DRY_RUN || sleep 25
ok "HDFS démarré."

# =============================================================================
# Étape 10 — Démarrage YARN
# =============================================================================
step 10 "Démarrage YARN — ResourceManager + NodeManager"
info "ResourceManager : ordonnancement (http://localhost:8088)"
info "NodeManager     : exécution des conteneurs YARN"
run "$COMPOSE_CMD up -d resourcemanager nodemanager"
$DRY_RUN || sleep 10
ok "YARN démarré."

# =============================================================================
# Étape 11 — Démarrage Flume + générateur de logs
# =============================================================================
step 11 "Démarrage Flume"
info "Flume : source netcat:44444 → channel mémoire → sink HDFS"
info "Sink HDFS écrit dans : hdfs://namenode:9000/flume/logs/"
info "Logs produits par les apps Node.js (dashboard + crud-app)."
run "$COMPOSE_CMD up -d flume"
$DRY_RUN || sleep 8
ok "Flume prêt à ingérer."

# =============================================================================
# Étape 12 — Démarrage Dashboard + Grafana + Caddy
# =============================================================================
step 12 "Démarrage interfaces"
info "Dashboard Node : http://localhost:5000  (console actions + flux)"
info "CRUD-app       : http://localhost:4000  (CRUD étudiants)"
info "Grafana        : http://localhost:3000  (admin / hadoop2026)"
info "Caddy proxy    : http://localhost       (nip.io)"
run "$COMPOSE_CMD up -d dashboard crud-app grafana caddy"
$DRY_RUN || sleep 5
ok "Interfaces lancées."

# =============================================================================
# Étape 13 — Healthcheck
# =============================================================================
step 13 "Vérification de santé du cluster"
if [ -x "$PROJECT_DIR/healthcheck.sh" ]; then
  run "$PROJECT_DIR/healthcheck.sh" || warn "Certains services pas encore prêts (réessayer dans 30s)."
else
  warn "healthcheck.sh introuvable — vérification manuelle conseillée."
fi

# =============================================================================
# Récapitulatif
# =============================================================================
echo -e "\n${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║                  Installation terminée ✓                     ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}\n"

cat <<EOF
${BOLD}Points d'accès :${NC}
  • HDFS NameNode UI    : http://localhost:9870
  • YARN ResourceMgr UI : http://localhost:8088
  • Dashboard Flume     : http://localhost:5000
  • Grafana             : http://localhost:3000   (admin / hadoop2026)
  • Reverse-proxy Caddy : http://localhost

${BOLD}Commandes utiles :${NC}
  • État         : $COMPOSE_CMD ps
  • Logs         : $COMPOSE_CMD logs -f <service>
  • Test HDFS    : ./scripts/test-hdfs.sh
  • Arrêt        : ./scripts/stop.sh
  • Réparation   : ./scripts/fix-namenode.sh

${BOLD}Pipeline de données :${NC}
  Apps Node.js (dashboard + crud-app) → Flume (netcat:44444) → HDFS (/flume/logs/) → Grafana
EOF

exit 0
__PROJECT_TEMPLATE__
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
wMKdeLr7u/u7+7v7i//+fzt6bosAmgEA
