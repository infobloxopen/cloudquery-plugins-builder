#!/usr/bin/env bash
# update-go-version.sh — Update go_version in plugins.yaml to the latest stable Go release.
#
# Usage: ./scripts/update-go-version.sh [OPTIONS]
#
# Options:
#   --dry-run   Report the latest eligible Go version without modifying files
#   --help      Show usage information
#
# See: specs/005-auto-update-dest-plugins/contracts/go-version-update.md
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=true; shift ;;
    --help|-h)
      echo "Usage: $0 [--dry-run] [--help]"
      echo ""
      echo "Updates the go_version field for all plugins in plugins.yaml to the"
      echo "latest stable Go release that has been available for at least 2 weeks."
      echo ""
      echo "Options:"
      echo "  --dry-run   Report eligible version without modifying files"
      echo "  --help      Show this help message"
      exit 0
      ;;
    *) error "Unknown argument: $1"; exit 1 ;;
  esac
done

MANIFEST="plugins.yaml"
STABILIZATION_DAYS=14

# ─── Main-branch guard ────────────────────────────────────────────────────────
# In CI, only allow updates on the main branch to prevent feature branch drift
if [[ "${CI:-}" == "true" ]]; then
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  if [[ "$CURRENT_BRANCH" != "main" ]]; then
    info "Not on main branch (current: ${CURRENT_BRANCH}). Exiting — no changes."
    exit 0
  fi
fi

# ─── Dependency check ─────────────────────────────────────────────────────────
for cmd in curl jq yq sort; do
  if ! command -v "$cmd" &>/dev/null; then
    error "Required command '$cmd' not found."
    exit 1
  fi
done

# ─── Fetch stable Go versions ────────────────────────────────────────────────
info "Fetching stable Go releases from go.dev..."

GO_RELEASES=$(curl -sSf "https://go.dev/dl/?mode=json" 2>/dev/null) || {
  error "Failed to fetch Go releases from go.dev"
  exit 1
}

# Extract stable version strings (newest first)
VERSIONS=$(echo "$GO_RELEASES" | jq -r '.[].version' | sed 's/^go//')

# ─── Current version from manifest ───────────────────────────────────────────
CURRENT_GO_VERSION=$(yq '.plugins[0].build.go_version' "$MANIFEST")
info "Current Go version in manifest: ${CURRENT_GO_VERSION}"

# ─── Find eligible version (newest stable ≥ STABILIZATION_DAYS old) ──────────
CUTOFF_EPOCH=$(date -v-${STABILIZATION_DAYS}d +%s 2>/dev/null || date -d "${STABILIZATION_DAYS} days ago" +%s)

# Construct GitHub API auth header if token available
GITHUB_AUTH=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  GITHUB_AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

CANDIDATE=""
CANDIDATE_DATE=""

for VERSION in $VERSIONS; do
  GO_TAG="go${VERSION}"

  # Resolve release date via GitHub API (tag → commit → committer date)
  TAG_REF=$(curl -sSf "${GITHUB_AUTH[@]}" \
    "https://api.github.com/repos/golang/go/git/ref/tags/${GO_TAG}" 2>/dev/null) || {
    warn "Failed to fetch GitHub ref for ${GO_TAG}, skipping"
    continue
  }

  TAG_TYPE=$(echo "$TAG_REF" | jq -r '.object.type')
  TAG_SHA=$(echo "$TAG_REF" | jq -r '.object.sha')

  # For annotated tags, dereference to the commit
  if [[ "$TAG_TYPE" == "tag" ]]; then
    TAG_OBJ=$(curl -sSf "${GITHUB_AUTH[@]}" \
      "https://api.github.com/repos/golang/go/git/tags/${TAG_SHA}" 2>/dev/null) || {
      warn "Failed to dereference tag ${GO_TAG}, skipping"
      continue
    }
    COMMIT_SHA=$(echo "$TAG_OBJ" | jq -r '.object.sha')
  else
    COMMIT_SHA="$TAG_SHA"
  fi

  COMMIT_INFO=$(curl -sSf "${GITHUB_AUTH[@]}" \
    "https://api.github.com/repos/golang/go/git/commits/${COMMIT_SHA}" 2>/dev/null) || {
    warn "Failed to fetch commit for ${GO_TAG}, skipping"
    continue
  }

  RELEASE_DATE=$(echo "$COMMIT_INFO" | jq -r '.committer.date')
  RELEASE_EPOCH=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$RELEASE_DATE" +%s 2>/dev/null \
    || date -d "$RELEASE_DATE" +%s 2>/dev/null)

  if [[ "$RELEASE_EPOCH" -le "$CUTOFF_EPOCH" ]]; then
    CANDIDATE="$VERSION"
    CANDIDATE_DATE="$RELEASE_DATE"
    break
  fi
done

# ─── Evaluate candidate ──────────────────────────────────────────────────────
if [[ -z "$CANDIDATE" ]]; then
  info "No Go version meets the ${STABILIZATION_DAYS}-day stabilization criterion"
  exit 0
fi

info "Latest eligible Go release: go${CANDIDATE} (released ${CANDIDATE_DATE%%T*}, ${STABILIZATION_DAYS}+ days ago)"

if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo "Current: ${CURRENT_GO_VERSION}"
  echo "Eligible: ${CANDIDATE}"
  if [[ "$CANDIDATE" != "$CURRENT_GO_VERSION" ]] && \
     [[ "$(printf '%s\n%s' "$CANDIDATE" "$CURRENT_GO_VERSION" | sort -V | tail -n1)" == "$CANDIDATE" ]]; then
    echo "Status: UPDATE AVAILABLE"
  else
    echo "Status: up to date"
  fi
  exit 0
fi

# No downgrade guard
NEWEST=$(printf '%s\n%s' "$CANDIDATE" "$CURRENT_GO_VERSION" | sort -V | tail -n1)
if [[ "$NEWEST" != "$CANDIDATE" || "$CANDIDATE" == "$CURRENT_GO_VERSION" ]]; then
  info "Go ${CURRENT_GO_VERSION} is already current (candidate: ${CANDIDATE}). No update needed."
  exit 0
fi

# ─── Apply update ─────────────────────────────────────────────────────────────
info "Updating all plugins from go_version ${CURRENT_GO_VERSION} → ${CANDIDATE}"

PLUGIN_COUNT=$(yq '.plugins | length' "$MANIFEST")
for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  yq -i ".plugins[${i}].build.go_version = \"${CANDIDATE}\"" "$MANIFEST"
done

info "Updated go_version for ${PLUGIN_COUNT} plugins to ${CANDIDATE}"
