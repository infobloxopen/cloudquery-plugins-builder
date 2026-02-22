#!/usr/bin/env bash
# detect-new-plugins.sh — Find destination plugins in the fork not listed in plugins.yaml.
#
# Usage: ./scripts/detect-new-plugins.sh [--manifest FILE]
#
# Queries the Infoblox CloudQuery fork for all plugins-destination-* tags and
# reports plugin names that are not present in the manifest.
set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

MANIFEST="${1:-plugins.yaml}"

# ─── Dependency check ─────────────────────────────────────────────────────────
for cmd in yq git sort; do
  if ! command -v "$cmd" &>/dev/null; then
    error "Required command '$cmd' not found."
    exit 1
  fi
done

FORK_REPO=$(yq '.plugins[0].upstream.repo' "$MANIFEST")

info "Scanning ${FORK_REPO} for destination plugin tags..."

ALL_TAGS=$(git ls-remote --tags "$FORK_REPO" 'refs/tags/plugins-destination-*' 2>/dev/null) || {
  error "Failed to fetch tags from ${FORK_REPO}"
  exit 1
}

# Extract unique plugin names from fork tags
FORK_NAMES=$(echo "$ALL_TAGS" \
  | grep -oE 'plugins-destination-[a-z0-9-]+-v[0-9]' \
  | sed -E 's/^plugins-destination-//; s/-v[0-9]$//' \
  | sort -u)

# Known plugin names from manifest
KNOWN_NAMES=$(yq '.plugins[].name' "$MANIFEST" | sort)

# Find plugins in fork but not in manifest
NEW_PLUGINS=()
while IFS= read -r fork_name; do
  if [[ -z "$fork_name" ]]; then continue; fi
  if ! echo "$KNOWN_NAMES" | grep -qx "$fork_name"; then
    NEW_PLUGINS+=("$fork_name")
  fi
done <<< "$FORK_NAMES"

FORK_COUNT=$(echo "$FORK_NAMES" | wc -l | tr -d ' ')
KNOWN_COUNT=$(echo "$KNOWN_NAMES" | wc -l | tr -d ' ')

info "Found ${FORK_COUNT} destination plugins in fork, ${KNOWN_COUNT} in manifest"

if [[ ${#NEW_PLUGINS[@]} -eq 0 ]]; then
  info "No new plugins detected — manifest is up to date"
  exit 0
fi

warn "New destination plugins detected (not in manifest):"
for name in "${NEW_PLUGINS[@]}"; do
  echo "  - ${name}"
done

echo ""
info "To add a new plugin, see the quickstart guide or run:"
info "  1. Look up the latest tag: git ls-remote --tags ${FORK_REPO} 'refs/tags/plugins-destination-<name>-v*'"
info "  2. Add an entry to plugins.yaml"
info "  3. Run: make validate"
