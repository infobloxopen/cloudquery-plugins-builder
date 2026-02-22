#!/usr/bin/env bash
# update-plugins.sh — Detect and apply new plugin versions from the Infoblox fork.
#
# Usage: ./scripts/update-plugins.sh [OPTIONS]
#
# Options:
#   --dry-run   Report available updates without modifying files
#   --commit    Create a git commit with the changes (for CI use)
#   --help      Show usage information
#
# See: specs/005-auto-update-dest-plugins/contracts/update-script.md
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
DRY_RUN=false
COMMIT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=true; shift ;;
    --commit)   COMMIT=true; shift ;;
    --help|-h)
      echo "Usage: $0 [--dry-run] [--commit] [--help]"
      echo ""
      echo "Checks the Infoblox CloudQuery fork for newer stable destination"
      echo "plugin releases and updates plugins.yaml accordingly."
      echo ""
      echo "Options:"
      echo "  --dry-run   Report available updates without modifying files"
      echo "  --commit    Create a git commit with the changes (for CI use)"
      echo "  --help      Show this help message"
      exit 0
      ;;
    *) error "Unknown argument: $1"; exit 1 ;;
  esac
done

MANIFEST="plugins.yaml"

# ─── Dependency check ─────────────────────────────────────────────────────────
for cmd in yq git sort grep sed; do
  if ! command -v "$cmd" &>/dev/null; then
    error "Required command '$cmd' not found."
    exit 1
  fi
done

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Retry a command up to N times with exponential backoff
retry() {
  local max_attempts=$1; shift
  local attempt=1
  local delay=1
  while [[ $attempt -le $max_attempts ]]; do
    if "$@" 2>/dev/null; then
      return 0
    fi
    if [[ $attempt -lt $max_attempts ]]; then
      warn "Attempt $attempt/$max_attempts failed, retrying in ${delay}s..."
      sleep "$delay"
      delay=$((delay * 2))
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

# Extract semver from a tag like "plugins-destination-kafka-v5.7.1" → "v5.7.1"
extract_version() {
  echo "$1" | sed -E 's/^plugins-destination-[a-z0-9-]+-//'
}

# Compare two semver strings. Returns 0 if $1 > $2 (newer), 1 otherwise
is_newer() {
  local v1="${1#v}" v2="${2#v}"
  local newest
  newest=$(printf '%s\n%s' "$v1" "$v2" | sort -V | tail -n1)
  [[ "$newest" == "$v1" && "$v1" != "$v2" ]]
}

# Extract major version number from semver: v8.14.1 → 8
major_version() {
  echo "${1#v}" | cut -d. -f1
}

# ─── Fetch all destination tags from fork ─────────────────────────────────────
PLUGIN_COUNT=$(yq '.plugins | length' "$MANIFEST")
FORK_REPO=$(yq '.plugins[0].upstream.repo' "$MANIFEST")

info "Fetching destination plugin tags from ${FORK_REPO}..."

ALL_TAGS=""
if ! ALL_TAGS=$(retry 3 git ls-remote --tags "$FORK_REPO" 'refs/tags/plugins-destination-*'); then
  error "Failed to fetch tags from ${FORK_REPO} after 3 attempts"
  exit 1
fi

# ─── Process each plugin ─────────────────────────────────────────────────────
UPDATED_PLUGINS=()
UPDATE_DETAILS=()

if [[ "$DRY_RUN" == "true" ]]; then
  printf "\n%-20s %-12s %-12s %s\n" "Plugin" "Current" "Available" "Status"
  printf "%-20s %-12s %-12s %s\n" "────────────────────" "────────────" "────────────" "──────────────────"
fi

for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  NAME=$(yq ".plugins[${i}].name" "$MANIFEST")
  KIND=$(yq ".plugins[${i}].kind" "$MANIFEST")
  CURRENT_VERSION=$(yq ".plugins[${i}].version" "$MANIFEST")

  # Filter stable tags for this plugin: plugins-destination-<name>-vX.Y.Z
  LATEST_TAG=$(echo "$ALL_TAGS" \
    | grep -E "refs/tags/plugins-${KIND}-${NAME}-v[0-9]+\.[0-9]+\.[0-9]+$" \
    | sed 's|.*refs/tags/||' \
    | sort -t'-' -k4,4V \
    | tail -1) || true

  if [[ -z "$LATEST_TAG" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      printf "%-20s %-12s %-12s %s\n" "$NAME" "$CURRENT_VERSION" "—" "no tags found"
    else
      warn "${NAME}: no stable tags found in fork"
    fi
    continue
  fi

  LATEST_VERSION=$(extract_version "$LATEST_TAG")
  LATEST_SHA=$(echo "$ALL_TAGS" | grep "refs/tags/${LATEST_TAG}$" | awk '{print $1}' | head -1)

  if [[ "$DRY_RUN" == "true" ]]; then
    if is_newer "$LATEST_VERSION" "$CURRENT_VERSION"; then
      printf "%-20s %-12s %-12s %s\n" "$NAME" "$CURRENT_VERSION" "$LATEST_VERSION" "UPDATE AVAILABLE"
    else
      printf "%-20s %-12s %-12s %s\n" "$NAME" "$CURRENT_VERSION" "$LATEST_VERSION" "up to date"
    fi
    continue
  fi

  # Check if update is needed
  if ! is_newer "$LATEST_VERSION" "$CURRENT_VERSION"; then
    info "${NAME}: ${CURRENT_VERSION} — up to date"
    continue
  fi

  info "${NAME}: ${CURRENT_VERSION} → ${LATEST_VERSION} (tag: ${LATEST_TAG})"

  # Update manifest fields
  yq -i ".plugins[${i}].version = \"${LATEST_VERSION}\"" "$MANIFEST"
  yq -i ".plugins[${i}].upstream.tag = \"${LATEST_TAG}\"" "$MANIFEST"
  yq -i ".plugins[${i}].upstream.commit = \"${LATEST_SHA}\"" "$MANIFEST"

  # Check for major version bump → update ldflags_version_path
  CURRENT_MAJOR=$(major_version "$CURRENT_VERSION")
  NEW_MAJOR=$(major_version "$LATEST_VERSION")
  if [[ "$CURRENT_MAJOR" != "$NEW_MAJOR" ]]; then
    CURRENT_LDFLAGS=$(yq ".plugins[${i}].build.ldflags_version_path" "$MANIFEST")
    NEW_LDFLAGS=${CURRENT_LDFLAGS///v${CURRENT_MAJOR}\///v${NEW_MAJOR}/}
    yq -i ".plugins[${i}].build.ldflags_version_path = \"${NEW_LDFLAGS}\"" "$MANIFEST"
    info "  Updated ldflags path: v${CURRENT_MAJOR} → v${NEW_MAJOR}"
  fi

  UPDATED_PLUGINS+=("$NAME")
  UPDATE_DETAILS+=("  - ${NAME}: ${CURRENT_VERSION} → ${LATEST_VERSION}")
done

if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  exit 0
fi

# ─── Detect new plugins not in manifest ───────────────────────────────────────
KNOWN_NAMES=$(yq '.plugins[].name' "$MANIFEST" | sort)
FORK_NAMES=$(echo "$ALL_TAGS" \
  | grep -oE 'plugins-destination-[a-z0-9-]+-v[0-9]' \
  | sed -E 's/^plugins-destination-//; s/-v[0-9]$//' \
  | sort -u)

NEW_PLUGINS=()
while IFS= read -r fork_name; do
  if ! echo "$KNOWN_NAMES" | grep -qx "$fork_name"; then
    NEW_PLUGINS+=("$fork_name")
  fi
done <<< "$FORK_NAMES"

if [[ ${#NEW_PLUGINS[@]} -gt 0 ]]; then
  warn "New plugins detected (not in manifest): ${NEW_PLUGINS[*]}"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
if [[ ${#UPDATED_PLUGINS[@]} -eq 0 ]]; then
  info "All plugins are up to date — no changes made"
  exit 0
fi

info "${#UPDATED_PLUGINS[@]} plugin(s) updated, $((PLUGIN_COUNT - ${#UPDATED_PLUGINS[@]})) up to date"

# ─── Commit if requested ──────────────────────────────────────────────────────
if [[ "$COMMIT" == "true" ]]; then
  COMMIT_BODY=$(printf '%s\n' "${UPDATE_DETAILS[@]}")
  COMMIT_MSG=$(printf 'chore: update plugin versions\n\nUpdated plugins:\n%s\n\nSigned-off-by: github-actions[bot] <github-actions[bot]@users.noreply.github.com>' "$COMMIT_BODY")

  git add "$MANIFEST"
  git commit -m "$COMMIT_MSG"
  info "Changes committed"
fi
