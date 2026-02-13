# ADR 002: Distroless Base Image

**Date**: 2026-02-12
**Status**: Accepted
**Decision**: D2 — Distroless over Alpine

## Context

We need to choose a base image for the final stage of our multi-stage Dockerfile. The image will run a statically-linked Go binary (the CloudQuery plugin gRPC server) as a non-root user. Security and minimal attack surface are priorities per Constitution Article III.

## Decision

We use `gcr.io/distroless/static-debian12:nonroot` as the final stage base image.

## Alternatives Considered

### 1. Alpine Linux (`alpine:3.x`)
- **Pros**: Small (~7MB), includes shell and package manager for debugging, well-known
- **Cons**: Includes shell (attack surface), musl libc (not needed for static Go binaries), package manager is unnecessary weight
- **Rejected**: Shell and package manager violate Constitution Article III (minimal attack surface) and FR-018 (no shell unless justified)

### 2. Scratch (`FROM scratch`)
- **Pros**: Absolute minimum (0 bytes base), no attack surface beyond the binary
- **Cons**: No CA certificates, no timezone data, no `/etc/passwd` (no user identity), no `/tmp` directory. Requires manually adding these.
- **Rejected**: Too much manual setup; distroless provides these essentials out of the box

### 3. Ubuntu/Debian slim
- **Pros**: Full glibc, familiar debugging tools
- **Cons**: ~80MB+ base, includes shell, package manager, many unnecessary packages
- **Rejected**: Far too large and insecure for a production container running a single static binary

## Consequences

- **Positive**: No shell, no package manager — significantly reduced attack surface
- **Positive**: Includes CA certificates, timezone data, and a `nonroot` user (UID 65534)
- **Positive**: ~2MB base image — final images are <30MB for most plugins
- **Negative**: No shell for debugging — must use `docker cp` or ephemeral debug containers
- **Mitigation**: Debug builds can use `gcr.io/distroless/static-debian12:debug` which includes a busybox shell
