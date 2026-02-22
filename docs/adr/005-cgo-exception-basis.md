# ADR 005: CGO on an Exception Basis

**Date**: 2026-06-15
**Status**: Accepted
**Decision**: D5 — CGO opt-in via manifest field, static builds by default

## Context

Most CloudQuery destination plugins are pure Go and compile to fully static binaries (`CGO_ENABLED=0`). However, two plugins — **sqlite** and **duckdb** — depend on C libraries (SQLite3 and DuckDB respectively) and require CGO to build.

Our Dockerfile (ADR 002) uses `gcr.io/distroless/static-debian12:nonroot` as the base image, which contains no C runtime. CGO-linked binaries crash at startup on this image because they need glibc and libgcc.

We need a mechanism to support CGO plugins without affecting the security posture or build simplicity of the 19 non-CGO plugins.

## Decision

CGO is enabled on a **per-plugin exception basis** controlled by a `cgo_required` boolean field in the plugin manifest (`plugins.yaml`). The field defaults to `false`.

When `cgo_required: true`:
- `CGO_ENABLED=1` is passed as a Docker build arg
- The final stage base image switches to `gcr.io/distroless/cc-debian12:nonroot` (which includes glibc and libgcc)

When `cgo_required: false` (default):
- `CGO_ENABLED=0` is passed (static binary)
- The final stage uses `gcr.io/distroless/static-debian12:nonroot` (no C runtime)

### Implementation Details

1. **Schema enforcement**: `cgo_required` is declared in `plugins-manifest.schema.json` under `$defs.build` with `type: boolean, default: false`
2. **Dockerfile**: Two build args — `CGO_ENABLED` (Stage 1) and `BASE_IMAGE` (Stage 3) — allow the same Dockerfile for all plugins
3. **build.sh**: Reads `cgo_required` from manifest and derives both build args automatically
4. **generate-matrix.sh**: Includes `cgo_required` in CI matrix output for potential future per-plugin CI logic

## Alternatives Considered

### 1. Separate Dockerfiles for CGO plugins
- **Pros**: Complete isolation of CGO build logic
- **Cons**: Duplicated build logic, two files to maintain, divergent build paths
- **Rejected**: Build args achieve the same result with a single Dockerfile

### 2. Always enable CGO for all plugins
- **Pros**: Simpler logic — no per-plugin branching
- **Cons**: All images would need `cc-debian12` base (~20MB larger), CGO cross-compilation is fragile, static Go binaries are faster to start
- **Rejected**: Violates Constitution Article III (minimal footprint) for 19 plugins that don't need it

### 3. Build CGO plugins outside Docker
- **Pros**: Could use host C toolchain directly
- **Cons**: Non-reproducible builds, host dependency on gcc/clang, breaks CI portability
- **Rejected**: Docker multi-stage builds already include gcc in the builder stage

## Current CGO Plugins

| Plugin | Reason | C Dependency |
|--------|--------|-------------|
| sqlite | Uses `mattn/go-sqlite3` which wraps SQLite3 via cgo | libsqlite3 (bundled in Go module) |
| duckdb | Uses `marcboeker/go-duckdb` which wraps DuckDB via cgo | libduckdb (bundled in Go module) |

## Consequences

- **Positive**: 19 of 21 plugins remain fully static with minimal base image (~2MB)
- **Positive**: CGO plugins work correctly with glibc runtime from `cc-debian12` (~20MB)
- **Positive**: Adding a new CGO plugin requires only setting `cgo_required: true` in manifest
- **Positive**: Schema validation prevents typos — field is boolean, not a string
- **Negative**: CGO plugin images are ~18MB larger due to `cc-debian12` base
- **Negative**: CGO builds are slower due to C compilation step
- **Mitigation**: Only 2 of 21 plugins (9.5%) pay this cost; the field is opt-in by design
