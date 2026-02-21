# Data Model: Rename Destination Plugin OCI Images

**Feature**: 003-rename-dest-images  
**Date**: 2026-02-21

## Entities

This feature does not introduce new entities. It modifies the **image naming derivation** applied to existing entities from the 001-oci-image-pipeline data model. The following updates the image reference pattern.

### Plugin Manifest Entry (unchanged structure)

Source: `plugins.yaml`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `plugins[].name` | string | ✅ | Plugin short name (e.g., `s3`, `postgresql`, `xkcd`) |
| `plugins[].kind` | string | ✅ | Plugin kind — constrained to `source` or `destination` by JSON Schema |
| `plugins[].version` | string | ✅ | Semantic version with `v` prefix (e.g., `v7.10.2`) |
| `plugins[].upstream.repo` | string | ✅ | Upstream Git repository URL |
| `plugins[].upstream.tag` | string | ✅ | Upstream Git tag |
| `plugins[].upstream.commit` | string | ✅ | Upstream commit SHA |
| `plugins[].build.*` | object | ✅ | Build parameters (plugin_dir, go_version, etc.) |

### OCI Image Reference (UPDATED pattern)

**Old pattern** (abandoned):
```
ghcr.io/<org>/cloudquery-plugin-<name>:<version>
```

**New pattern**:
```
ghcr.io/<org>/cq-<kind>-<name>:<version>
```

**Derivation formula**:
```
IMAGE = "${REGISTRY}/${ORG}/cq-${KIND}-${NAME}:${VERSION}"
```

Where:
- `REGISTRY` = `ghcr.io` (hardcoded)
- `ORG` = GitHub repository owner (e.g., `infobloxopen`)
- `KIND` = `plugins[].kind` from manifest (e.g., `source`, `destination`)
- `NAME` = `plugins[].name` from manifest (e.g., `s3`, `postgresql`)
- `VERSION` = `plugins[].version` from manifest (e.g., `v7.10.2`)

**Examples**:

| Name | Kind | Version | Image Reference |
|------|------|---------|-----------------|
| `s3` | `destination` | `v7.10.2` | `ghcr.io/infobloxopen/cq-destination-s3:v7.10.2` |
| `postgresql` | `destination` | `v8.14.1` | `ghcr.io/infobloxopen/cq-destination-postgresql:v8.14.1` |
| `file` | `destination` | `v5.5.1` | `ghcr.io/infobloxopen/cq-destination-file:v5.5.1` |
| `xkcd` | `source` | `v1.0.0` | `ghcr.io/infobloxopen/cq-source-xkcd:v1.0.0` |

### OCI Labels (UPDATED values)

| Label | Old Value | New Value |
|-------|-----------|-----------|
| `org.opencontainers.image.title` | `cloudquery-plugin-<name>` | `cq-<kind>-<name>` |
| `org.opencontainers.image.description` | `CloudQuery <kind> plugin <name> <version>` | (unchanged) |
| `io.cloudquery.plugin.kind` | `<kind>` | (unchanged) |
| `io.cloudquery.plugin.name` | `<name>` | (unchanged) |

### Build Index Record (UPDATED image field)

Source: per-plugin metadata JSON emitted by `publish.yaml`

| Field | Type | Description |
|-------|------|-------------|
| `plugin_kind` | string | Plugin kind (unchanged) |
| `plugin_name` | string | Plugin short name (unchanged) |
| `version` | string | Plugin version (unchanged) |
| `image` | string | **Updated**: `ghcr.io/<org>/cq-<kind>-<name>:<version>` |
| `upstream_repo` | string | Upstream repo URL (unchanged) |
| `upstream_tag` | string | Upstream tag (unchanged) |
| `upstream_commit` | string | Upstream commit SHA (unchanged) |
| `build_timestamp` | string | RFC-3339 timestamp (unchanged) |

### Kubernetes Resource Names (UPDATED in examples)

Example manifests use the image name as the basis for K8s resource names and label selectors:

| Resource | Old Name | New Name |
|----------|----------|----------|
| Deployment | `cloudquery-plugin-<name>` | `cq-destination-<name>` |
| Service | `cloudquery-plugin-<name>` | `cq-destination-<name>` |
| Pod label `app` | `cloudquery-plugin-<name>` | `cq-destination-<name>` |
| gRPC path | `cloudquery-plugin-<name>:7777` | `cq-destination-<name>:7777` |

## Validation Rules

1. `kind` MUST be one of `["source", "destination"]` (enforced by JSON Schema + build.sh guard)
2. `name` MUST match `^[a-z][a-z0-9-]*$` (existing schema constraint)
3. The combination `cq-<kind>-<name>` MUST be a valid OCI repository name (≤128 chars, lowercase alphanumeric + hyphens)

## State Transitions

N/A — no state machines affected. The image naming is a pure derivation from static manifest fields.
