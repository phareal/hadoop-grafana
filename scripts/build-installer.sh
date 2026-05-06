#!/usr/bin/env bash
# =============================================================================
# build-installer.sh — Régénère le payload tarball embarqué dans install.sh
# -----------------------------------------------------------------------------
# Lit tous les fichiers du projet (sauf exclusions), crée tarball gzip,
# base64-encode, remplace la section après __PROJECT_TEMPLATE__ dans install.sh.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$PROJECT_DIR/scripts/install.sh"
MARKER="__PROJECT_TEMPLATE__"

cd "$PROJECT_DIR"

# Désactiver AppleDouble (macOS) — évite les fichiers ._* dans tarball
export COPYFILE_DISABLE=1
export COPY_EXTENDED_ATTRIBUTES_DISABLE=1

if [ ! -f "$INSTALLER" ]; then
  echo "✗ install.sh introuvable : $INSTALLER" >&2
  exit 1
fi

if ! grep -q "^${MARKER}$" "$INSTALLER"; then
  echo "✗ Marqueur ${MARKER} absent de install.sh" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "→ Création du tarball..."
# Liste triée des fichiers à embarquer (ordre stable → tarball reproductible)
find . -type f \
  -not -path './data/*' \
  -not -path './.git/*' \
  -not -path './.idea/*' \
  -not -path './.claude/*' \
  -not -path './scripts/install.sh' \
  -not -path './scripts/build-installer.sh' \
  -not -path './Makefile' \
  -not -path './slides.md' \
  -not -name '*.pyc' \
  -not -path '*/__pycache__/*' \
  -not -name '.DS_Store' \
  -not -name '._*' \
  -not -name '.AppleDouble' \
  | LC_ALL=C sort > "$TMP/files.list"

# Build reproductible : copier dans staging, fixer mtime, puis tar
# (bsdtar n'accepte pas --mtime, GNU tar oui — on uniformise via staging)
STAGE="$TMP/stage"
mkdir -p "$STAGE"
while IFS= read -r f; do
  rel="${f#./}"
  mkdir -p "$STAGE/$(dirname "$rel")"
  # cp SANS -p : on ne préserve ni mtime ni xattrs (évite warnings sur GNU tar)
  cp "$f" "$STAGE/$rel"
done < "$TMP/files.list"

# Strip xattrs macOS (com.apple.provenance, com.apple.quarantine, etc.)
if command -v xattr >/dev/null 2>&1; then
  find "$STAGE" -exec xattr -c {} + 2>/dev/null || true
fi

# mtime fixé sur tous les fichiers (touch -t YYYYMMDDhhmm)
find "$STAGE" -exec touch -t 202601010000 {} +

# Création tarball depuis staging — bsdtar : --no-xattrs strip métadonnées étendues
TAR_OPTS=()
if tar --version 2>/dev/null | grep -qi bsdtar; then
  TAR_OPTS=(--no-xattrs --no-mac-metadata)
fi
( cd "$STAGE" && find . -type f | LC_ALL=C sort | \
    tar "${TAR_OPTS[@]}" -cf "$TMP/project.tar" -T - )
gzip -n -9 "$TMP/project.tar"

SIZE=$(wc -c < "$TMP/project.tar.gz" | tr -d ' ')
COUNT=$(tar -tzf "$TMP/project.tar.gz" 2>/dev/null | grep -v '/$' | wc -l | tr -d ' ')
echo "  Tarball : $SIZE octets, $COUNT fichiers"

echo "→ Encodage base64 (76 colonnes)..."
base64 < "$TMP/project.tar.gz" | fold -w 76 > "$TMP/payload.b64"

echo "→ Réécriture de install.sh..."
# Garder tout jusqu'au marqueur inclus, puis ajouter le payload
awk -v marker="$MARKER" '
  { print }
  $0 == marker { exit }
' "$INSTALLER" > "$TMP/install.sh.new"

cat "$TMP/payload.b64" >> "$TMP/install.sh.new"

# Vérif syntaxe avant remplacement
if ! bash -n "$TMP/install.sh.new"; then
  echo "✗ Syntaxe install.sh cassée — abandon" >&2
  exit 1
fi

mv "$TMP/install.sh.new" "$INSTALLER"
chmod +x "$INSTALLER"

NEW_SIZE=$(wc -c < "$INSTALLER" | tr -d ' ')
NEW_LINES=$(wc -l < "$INSTALLER" | tr -d ' ')
echo "✓ install.sh régénéré : $NEW_SIZE octets, $NEW_LINES lignes"
