#!/usr/bin/env bash
# build-all.sh — Build all plugins defined in plugins.yaml.
#
# Usage: ./scripts/build-all.sh [--push]
#
# Iterates over all plugins in the manifest and calls build.sh for each.
# Reports a summary of successes and failures at the end.
set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ─── Args ─────────────────────────────────────────────────────────────────────
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
  EXTRA_ARGS+=("$1")
  shift
done

MANIFEST="plugins.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Dependency check ─────────────────────────────────────────────────────────
for cmd in yq; do
  if ! command -v "$cmd" &>/dev/null; then
    error "Required command '$cmd' not found."
    exit 1
  fi
done

# ─── Build all plugins ───────────────────────────────────────────────────────
PLUGIN_NAMES=$(yq '.plugins[].name' "$MANIFEST")
TOTAL=$(echo "$PLUGIN_NAMES" | wc -l | tr -d ' ')
SUCCESSES=0
FAILURES=0
FAILED_PLUGINS=()

info "Building ${TOTAL} plugin(s) from ${MANIFEST}"
echo ""

for NAME in $PLUGIN_NAMES; do
  info "═══════════════════════════════════════════════════════════"
  info "Building plugin: ${NAME}"
  info "═══════════════════════════════════════════════════════════"

  if "${SCRIPT_DIR}/build.sh" "$NAME" "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"; then
    SUCCESSES=$((SUCCESSES + 1))
    info "✓ ${NAME} build succeeded"
  else
    FAILURES=$((FAILURES + 1))
    FAILED_PLUGINS+=("$NAME")
    error "✗ ${NAME} build failed"
  fi

  echo ""
done

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
info "═══════════════════════════════════════════════════════════"
info "Build Summary"
info "═══════════════════════════════════════════════════════════"
info "  Total:     ${TOTAL}"
info "  Succeeded: ${SUCCESSES}"

if [[ "$FAILURES" -gt 0 ]]; then
  error "  Failed:    ${FAILURES} (${FAILED_PLUGINS[*]})"
  exit 1
else
  info "  Failed:    0"
  info "All plugins built successfully ✓"
fi
