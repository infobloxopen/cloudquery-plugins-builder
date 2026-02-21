# ADR 004: Rename Image Convention to `cq-{kind}-{name}`

**Date**: 2025-07-24
**Status**: Accepted
**Decision**: Replace `cloudquery-plugin-{name}` with `cq-{kind}-{name}` for all OCI image names

## Context

All plugin images were previously named `cloudquery-plugin-{name}` regardless of whether the plugin was a source or destination type. This created ambiguity — users could not distinguish source from destination plugins by image name alone. With source plugins coming (e.g., XKCD), a naming collision would occur since a source and destination plugin could share the same `{name}`.

The `kind` field (`source` or `destination`) already existed in `plugins.yaml` and was propagated through the entire build pipeline (matrix generation, CI action inputs, build script variables, OCI labels) but was never used in the image name.

## Decision

Adopt the naming convention `cq-{kind}-{name}:{version}` where:
- `cq` — short prefix for CloudQuery
- `{kind}` — `source` or `destination` (from `plugins.yaml`)
- `{name}` — plugin name (e.g., `postgresql`, `s3`, `file`)
- `{version}` — semver tag (e.g., `v8.14.1`)

Examples:
- `ghcr.io/infobloxopen/cq-destination-postgresql:v8.14.1`
- `ghcr.io/infobloxopen/cq-destination-s3:v7.10.2`
- `ghcr.io/infobloxopen/cq-source-xkcd:v1.0.0`

No backward compatibility aliases are maintained. All consumers must update their image references.

## Alternatives Considered

### 1. Keep `cloudquery-plugin-{name}` (status quo)
- **Pros**: No migration needed
- **Cons**: Ambiguous, collision risk between source and destination plugins with the same name
- **Rejected**: Does not scale to multi-kind plugin set

### 2. `cloudquery-{kind}-plugin-{name}`
- **Pros**: Retains `cloudquery` prefix, explicit
- **Cons**: Verbose image names (40+ characters before tag)
- **Rejected**: Unnecessarily long; `cq` is the established abbreviation

### 3. `cq-plugin-{kind}-{name}`
- **Pros**: Groups all plugins under `cq-plugin-*`
- **Cons**: Less natural reading order; kind is buried mid-name
- **Rejected**: `cq-{kind}-{name}` reads more naturally (e.g., "cq destination postgresql")

## Consequences

- All downstream Kubernetes manifests referencing old image names must be updated
- CI build metadata (`build-index.json`) will contain new image names automatically
- OCI title labels updated to match new image name
- `kind` validation guard added to `build.sh` for defense-in-depth
