#!/usr/bin/env bash
# build.sh — Build a single plugin image locally.
#
# Usage: ./scripts/build.sh <plugin-name> [--push] [--platform PLATFORMS]
#
# Arguments:
#   plugin-name  — Name of the plugin as defined in plugins.yaml (e.g., "postgresql")
#   --push       — Push the image to the registry after building
#   --platform   — Comma-separated platforms (default: linux/amd64 for local, linux/amd64,linux/arm64 for push)
#
# The script extracts the plugin's configuration from plugins.yaml and invokes
# docker buildx build with the correct build args.
set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ─── Args ─────────────────────────────────────────────────────────────────────
PLUGIN_NAME="${1:?Usage: build.sh <plugin-name> [--push] [--platform PLATFORMS]}"
shift

PUSH=false
PLATFORMS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)     PUSH=true; shift ;;
    --platform) PLATFORMS="$2"; shift 2 ;;
    *)          error "Unknown argument: $1"; exit 1 ;;
  esac
done

MANIFEST="plugins.yaml"
IMAGE_ORG="ghcr.io/infobloxopen"

# ─── Dependency check ─────────────────────────────────────────────────────────
for cmd in yq docker; do
  if ! command -v "$cmd" &>/dev/null; then
    error "Required command '$cmd' not found."
    exit 1
  fi
done

# ─── Extract plugin config from manifest ──────────────────────────────────────
PLUGIN_INDEX=$(yq ".plugins | to_entries | .[] | select(.value.name == \"${PLUGIN_NAME}\") | .key" "$MANIFEST")

if [[ -z "$PLUGIN_INDEX" ]]; then
  error "Plugin '${PLUGIN_NAME}' not found in ${MANIFEST}"
  error "Available plugins: $(yq '.plugins[].name' "$MANIFEST" | tr '\n' ' ')"
  exit 1
fi

KIND=$(yq ".plugins[${PLUGIN_INDEX}].kind" "$MANIFEST")
VERSION=$(yq ".plugins[${PLUGIN_INDEX}].version" "$MANIFEST")
UPSTREAM_REPO=$(yq ".plugins[${PLUGIN_INDEX}].upstream.repo" "$MANIFEST")
UPSTREAM_TAG=$(yq ".plugins[${PLUGIN_INDEX}].upstream.tag" "$MANIFEST")
UPSTREAM_COMMIT=$(yq ".plugins[${PLUGIN_INDEX}].upstream.commit" "$MANIFEST")
PLUGIN_DIR=$(yq ".plugins[${PLUGIN_INDEX}].build.plugin_dir" "$MANIFEST")
GO_VERSION=$(yq ".plugins[${PLUGIN_INDEX}].build.go_version" "$MANIFEST")
BIN_NAME=$(yq ".plugins[${PLUGIN_INDEX}].build.bin_name // \"plugin\"" "$MANIFEST")
LDFLAGS_VERSION_PATH=$(yq ".plugins[${PLUGIN_INDEX}].build.ldflags_version_path // \"\"" "$MANIFEST")

IMAGE_NAME="${IMAGE_ORG}/cloudquery-plugin-${PLUGIN_NAME}:${VERSION}"

# Set default platforms
if [[ -z "$PLATFORMS" ]]; then
  if [[ "$PUSH" == "true" ]]; then
    PLATFORMS="linux/amd64,linux/arm64"
  else
    PLATFORMS="linux/amd64"
  fi
fi

# ─── Build ────────────────────────────────────────────────────────────────────
info "Building ${PLUGIN_NAME} ${VERSION}"
info "  Image:     ${IMAGE_NAME}"
info "  Platforms: ${PLATFORMS}"
info "  Upstream:  ${UPSTREAM_REPO} @ ${UPSTREAM_TAG}"
info "  Plugin:    ${PLUGIN_DIR}"

BUILD_ARGS=(
  --build-arg "GO_VERSION=${GO_VERSION}"
  --build-arg "PLUGIN_DIR=${PLUGIN_DIR}"
  --build-arg "PLUGIN_VERSION=${VERSION}"
  --build-arg "LDFLAGS_VERSION_PATH=${LDFLAGS_VERSION_PATH}"
  --build-arg "BIN_NAME=${BIN_NAME}"
  --build-arg "UPSTREAM_REPO=${UPSTREAM_REPO}"
  --build-arg "UPSTREAM_TAG=${UPSTREAM_TAG}"
)

# OCI labels per data-model.md § OCI Image
BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LABELS=(
  --label "org.opencontainers.image.source=https://github.com/infobloxopen/cloudquery-plugins-builder"
  --label "org.opencontainers.image.created=${BUILD_TIMESTAMP}"
  --label "org.opencontainers.image.version=${VERSION}"
  --label "org.opencontainers.image.title=cloudquery-plugin-${PLUGIN_NAME}"
  --label "org.opencontainers.image.description=CloudQuery ${KIND} plugin ${PLUGIN_NAME} ${VERSION}"
  --label "org.opencontainers.image.licenses=MPL-2.0"
  --label "io.cloudquery.plugin.kind=${KIND}"
  --label "io.cloudquery.plugin.name=${PLUGIN_NAME}"
  --label "io.cloudquery.plugin.upstream-repo=${UPSTREAM_REPO}"
  --label "io.cloudquery.plugin.upstream-tag=${UPSTREAM_TAG}"
  --label "io.cloudquery.plugin.upstream-commit=${UPSTREAM_COMMIT}"
)

BUILDX_ARGS=(
  --platform "$PLATFORMS"
  --tag "$IMAGE_NAME"
  "${BUILD_ARGS[@]}"
  "${LABELS[@]}"
)

if [[ "$PUSH" == "true" ]]; then
  BUILDX_ARGS+=(--push --sbom=true --provenance=mode=max)
else
  BUILDX_ARGS+=(--load)
fi

docker buildx build "${BUILDX_ARGS[@]}" .

info "Build complete: ${IMAGE_NAME}"
