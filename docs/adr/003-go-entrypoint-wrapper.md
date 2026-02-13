# ADR 003: Go Entrypoint Wrapper

**Date**: 2026-02-12
**Status**: Accepted
**Decision**: D3 — Go wrapper over shell script for env var bridging

## Context

CloudQuery plugin binaries accept a `--address` flag to set the gRPC listen address. In Kubernetes, operators need to override the listen address and port via environment variables (`CQ_PLUGIN_ADDRESS`, `CQ_PLUGIN_PORT`) without modifying the container command. We need a mechanism to bridge environment variables to CLI arguments.

## Decision

We use a thin Go binary (`cmd/entrypoint/main.go`) as the container's `ENTRYPOINT`. It reads `CQ_PLUGIN_ADDRESS` and `CQ_PLUGIN_PORT` environment variables, constructs the `--address` flag, and `exec`s the plugin binary (`/plugin`).

## Alternatives Considered

### 1. Shell script entrypoint (`entrypoint.sh`)
- **Pros**: Simple to write, widely understood, easy to modify
- **Cons**: Requires a shell in the final image — violates Constitution Article III (distroless, no shell). Adding bash/sh to distroless defeats its purpose.
- **Rejected**: Incompatible with distroless base image choice (ADR-002)

### 2. Direct environment variable support in plugin binary
- **Pros**: No wrapper needed, cleanest solution
- **Cons**: Requires upstream changes to CloudQuery plugin CLI. We don't control the upstream binary and cannot guarantee env var support.
- **Rejected**: We cannot modify upstream; this is an external dependency

### 3. Kubernetes command/args override
- **Pros**: No entrypoint wrapper needed
- **Cons**: Every deployment manifest must include the full command with address override. Error-prone, repetitive, and breaks the "just set an env var" UX.
- **Rejected**: Poor developer experience; env vars are the standard K8s pattern

## Consequences

- **Positive**: Works with distroless (no shell dependency) — statically linked Go binary
- **Positive**: Clean PID 1 behavior via `syscall.Exec` (no child process, proper signal handling)
- **Positive**: Standard K8s pattern — operators set env vars in Deployment spec
- **Positive**: Transparent — if no env vars are set, CMD args pass through unchanged
- **Negative**: Adds a build stage and ~1MB to the final image
- **Mitigation**: Build stage is cached; 1MB overhead is negligible vs. the plugin binary size (~20-50MB)
