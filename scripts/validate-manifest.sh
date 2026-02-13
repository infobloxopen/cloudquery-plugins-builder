#!/usr/bin/env bash
# validate-manifest.sh — Validate plugins.yaml against JSON Schema and verify upstream refs.
#
# Usage: ./scripts/validate-manifest.sh [--manifest FILE] [--schema FILE]
#
# Exit codes:
#   0 — all validations passed
#   1 — schema validation failed
#   2 — upstream tag verification failed
#   3 — upstream commit mismatch
#   4 — missing dependencies
set -euo pipefail

MANIFEST="${1:-plugins.yaml}"
SCHEMA="${2:-schemas/plugins-manifest.schema.json}"

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ─── Dependency check ─────────────────────────────────────────────────────────
for cmd in yq jq git; do
  if ! command -v "$cmd" &>/dev/null; then
    error "Required command '$cmd' not found. Please install it."
    exit 4
  fi
done

# Check for a JSON Schema validator
VALIDATOR=""
if command -v check-jsonschema &>/dev/null; then
  VALIDATOR="check-jsonschema"
elif command -v ajv &>/dev/null; then
  VALIDATOR="ajv"
else
  warn "No JSON Schema validator found (check-jsonschema or ajv). Skipping schema validation."
fi

# ─── Step 1: Schema validation ───────────────────────────────────────────────
info "Validating manifest schema: ${MANIFEST}"

if [[ -n "$VALIDATOR" ]]; then
  if [[ "$VALIDATOR" == "check-jsonschema" ]]; then
    VALIDATION_OUTPUT=$(check-jsonschema --schemafile "$SCHEMA" "$MANIFEST" 2>&1) || {
      error "Schema validation failed for ${MANIFEST}"
      echo ""
      echo "$VALIDATION_OUTPUT" | while IFS= read -r line; do
        error "  $line"
      done
      echo ""
      error "Hint: compare your manifest against the schema at ${SCHEMA}"
      error "Common issues:"
      error "  - Missing required field (name, kind, version, upstream, build)"
      error "  - Invalid version format (must match ^v\\d+\\.\\d+\\.\\d+)"
      error "  - Invalid commit SHA (must be 40 hex characters)"
      error "  - Invalid plugin kind (must be 'source' or 'destination')"
      # Emit GHA annotation if running in CI
      if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "::error file=${MANIFEST}::Schema validation failed. ${VALIDATION_OUTPUT//$'\n'/ }"
      fi
      exit 1
    }
  elif [[ "$VALIDATOR" == "ajv" ]]; then
    # Convert YAML to JSON for ajv
    TMPJSON=$(mktemp /tmp/manifest-XXXXXX.json)
    trap 'rm -f "$TMPJSON"' EXIT
    yq -o json "$MANIFEST" > "$TMPJSON"
    VALIDATION_OUTPUT=$(ajv validate -s "$SCHEMA" -d "$TMPJSON" --spec=draft2020 2>&1) || {
      error "Schema validation failed for ${MANIFEST}"
      echo ""
      echo "$VALIDATION_OUTPUT" | while IFS= read -r line; do
        error "  $line"
      done
      echo ""
      error "Hint: compare your manifest against the schema at ${SCHEMA}"
      if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "::error file=${MANIFEST}::Schema validation failed. ${VALIDATION_OUTPUT//$'\n'/ }"
      fi
      exit 1
    }
  fi
  info "Schema validation passed ✓"
else
  warn "Skipping schema validation (no validator installed)"
fi

# ─── Step 2: Verify upstream tags and commits ─────────────────────────────────
info "Verifying upstream references..."

PLUGIN_COUNT=$(yq '.plugins | length' "$MANIFEST")
FAILURES=0

for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  NAME=$(yq ".plugins[$i].name" "$MANIFEST")
  VERSION=$(yq ".plugins[$i].version" "$MANIFEST")
  REPO=$(yq ".plugins[$i].upstream.repo" "$MANIFEST")
  TAG=$(yq ".plugins[$i].upstream.tag" "$MANIFEST")
  COMMIT=$(yq ".plugins[$i].upstream.commit" "$MANIFEST")

  echo -n "  Checking ${NAME} ${VERSION} (tag: ${TAG})... "

  # Verify tag exists
  REMOTE_REF=$(git ls-remote --tags "$REPO" "$TAG" 2>/dev/null | awk '{print $1}' | head -1)

  if [[ -z "$REMOTE_REF" ]]; then
    echo ""
    error "Tag '${TAG}' not found in ${REPO}"
    error "  Plugin: ${NAME} ${VERSION}"
    error "  Suggestion: verify the tag exists at ${REPO}/releases"
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
      echo "::error file=${MANIFEST}::Plugin '${NAME}' v${VERSION}: tag '${TAG}' not found in upstream repo ${REPO}"
    fi
    FAILURES=$((FAILURES + 1))
    continue
  fi

  # Verify commit SHA matches
  if [[ "$REMOTE_REF" != "$COMMIT" ]]; then
    echo ""
    error "Commit SHA mismatch for ${NAME} ${VERSION}"
    error "  Expected: ${COMMIT}"
    error "  Actual:   ${REMOTE_REF}"
    error "  Tag:      ${TAG}"
    error "  Suggestion: update the commit field to '${REMOTE_REF}'"
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
      echo "::error file=${MANIFEST}::Plugin '${NAME}' v${VERSION}: commit SHA mismatch for tag '${TAG}'. Expected ${COMMIT}, got ${REMOTE_REF}."
    fi
    FAILURES=$((FAILURES + 1))
    continue
  fi

  echo "✓"
done

if [[ "$FAILURES" -gt 0 ]]; then
  error "${FAILURES} plugin(s) failed upstream verification"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${FAILURES} plugin(s) failed upstream reference verification"
  fi
  exit 2
fi

info "All upstream references verified ✓"
info "Validation complete — all checks passed"

info "All ${PLUGIN_COUNT} plugins passed upstream verification ✓"
