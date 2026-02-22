# ============================================================
# Generic multi-stage Dockerfile for CloudQuery plugin images
# All build parameters are injected via build args from plugins.yaml
# ============================================================

# ============================================================
# Stage 1: Build the plugin binary from upstream source
# ============================================================
ARG GO_VERSION=1.25.6
FROM golang:${GO_VERSION} AS plugin-builder

ARG PLUGIN_DIR=plugins/destination/postgresql
ARG PLUGIN_VERSION=v8.14.1
ARG LDFLAGS_VERSION_PATH=""
ARG BIN_NAME=plugin
ARG UPSTREAM_REPO=https://github.com/infobloxopen/cloudquery
ARG UPSTREAM_TAG=plugins-destination-postgresql-v8.14.1

# Clone upstream at the exact tag (shallow clone for speed)
RUN git clone --depth=1 --branch="${UPSTREAM_TAG}" "${UPSTREAM_REPO}" /src

WORKDIR /src/${PLUGIN_DIR}

# Download dependencies first (cached layer — only re-runs when go.mod/go.sum change)
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# Build static binary — no CGO, no external dependencies
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w -X ${LDFLAGS_VERSION_PATH}=${PLUGIN_VERSION}" \
    -o /${BIN_NAME} .

# ============================================================
# Stage 2: Build the entrypoint wrapper
# ============================================================
FROM golang:${GO_VERSION} AS entrypoint-builder

COPY cmd/entrypoint/go.mod cmd/entrypoint/go.sum* /build/
WORKDIR /build
RUN go mod download

COPY cmd/entrypoint/ /build/

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /entrypoint .

# ============================================================
# Stage 3: Final minimal image (distroless, non-root)
# ============================================================
FROM gcr.io/distroless/static-debian12:nonroot

# Copy binaries from builder stages
COPY --from=plugin-builder /plugin /plugin
COPY --from=entrypoint-builder /entrypoint /entrypoint

# Copy upstream license for compliance
COPY --from=plugin-builder /src/LICENSE /licenses/LICENSE

# gRPC server port
EXPOSE 7777

# Entrypoint wrapper bridges env vars to CLI args, then execs /plugin
ENTRYPOINT ["/entrypoint"]
CMD ["serve", "--address", "[::]:7777", "--log-format", "json", "--log-level", "info"]
