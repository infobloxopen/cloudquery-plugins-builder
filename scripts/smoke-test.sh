#!/usr/bin/env bash
# smoke-test.sh — Run a container and verify gRPC port accepts TCP connections.
#
# Usage: ./scripts/smoke-test.sh <image> [port] [timeout]
#
# Arguments:
#   image   — Full image reference (e.g., ghcr.io/infobloxopen/cq-destination-postgresql:v8.14.1)
#   port    — Port to check (default: 7777)
#   timeout — Max seconds to wait (default: 30)
#
# Exit codes:
#   0 — smoke test passed
#   1 — smoke test failed (port not reachable within timeout)
#   2 — container failed to start
set -euo pipefail

IMAGE="${1:?Usage: smoke-test.sh <image> [port] [timeout]}"
PORT="${2:-7777}"
TIMEOUT="${3:-30}"

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ─── Generate unique container name ──────────────────────────────────────────
CONTAINER_NAME="smoke-$(date +%s)-$$"

cleanup() {
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" 2>/dev/null; then
    info "Capturing container logs..."
    docker logs "$CONTAINER_NAME" 2>&1 | tail -20 || true
    info "Removing container ${CONTAINER_NAME}..."
    docker rm -f "$CONTAINER_NAME" &>/dev/null || true
  fi
}
trap cleanup EXIT

# ─── Start container ──────────────────────────────────────────────────────────
info "Starting container: ${IMAGE}"
info "Container name: ${CONTAINER_NAME}"
info "Checking port: ${PORT} (timeout: ${TIMEOUT}s)"

if ! docker run -d \
  --name "$CONTAINER_NAME" \
  -p "${PORT}:${PORT}" \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid \
  "$IMAGE" 2>/dev/null; then
  error "Failed to start container from image: ${IMAGE}"
  exit 2
fi

# ─── Wait for TCP connection ─────────────────────────────────────────────────
info "Waiting for TCP connection on port ${PORT}..."

ELAPSED=0
while [[ "$ELAPSED" -lt "$TIMEOUT" ]]; do
  # Check if container is still running
  if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" 2>/dev/null; then
    error "Container exited unexpectedly"
    docker logs "$CONTAINER_NAME" 2>&1 | tail -20 || true
    exit 2
  fi

  # Try TCP connection
  if nc -z localhost "$PORT" 2>/dev/null || (echo >/dev/tcp/localhost/"$PORT") 2>/dev/null; then
    info "Port ${PORT} is accepting connections after ${ELAPSED}s ✓"
    info "Smoke test PASSED for ${IMAGE}"
    exit 0
  fi

  sleep 1
  ELAPSED=$((ELAPSED + 1))
done

error "Port ${PORT} did not accept connections within ${TIMEOUT}s"
error "Smoke test FAILED for ${IMAGE}"
exit 1
