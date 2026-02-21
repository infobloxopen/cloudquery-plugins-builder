# Naming Convention Contract: OCI Image Names

**Feature**: 003-rename-dest-images  
**Date**: 2026-02-21  
**Status**: Draft

## Convention

All OCI images published by this repository MUST follow the naming pattern:

```
ghcr.io/<org>/cq-<kind>-<name>:<version>
```

Where:
- `<org>` is the GitHub organization (e.g., `infobloxopen`)
- `<kind>` is the plugin kind from `plugins.yaml` — one of `source` or `destination`
- `<name>` is the plugin short name from `plugins.yaml` (e.g., `s3`, `postgresql`, `xkcd`)
- `<version>` is the semantic version with `v` prefix (e.g., `v7.10.2`)

## Enforcement Points

The naming convention is enforced at three levels:

### 1. Schema Level (preventive)

File: `schemas/plugins-manifest.schema.json`

```json
"kind": {
  "type": "string",
  "enum": ["source", "destination"],
  "description": "Plugin kind."
}
```

CI validates the manifest against this schema before any build step runs.

### 2. Build Script Level (defense-in-depth)

File: `scripts/build.sh`

```bash
case "$KIND" in
  source|destination) ;;
  *) error "Unknown plugin kind '${KIND}' for plugin '${PLUGIN_NAME}'. Must be 'source' or 'destination'."; exit 1 ;;
esac

IMAGE_NAME="${IMAGE_ORG}/cq-${KIND}-${PLUGIN_NAME}:${VERSION}"
```

### 3. CI Action Level (authoritative for CI builds)

File: `.github/actions/build-plugin/action.yaml`

```yaml
IMAGE="${{ inputs.registry }}/cq-${{ inputs.kind }}-${{ inputs.name }}:${{ inputs.version }}"
```

## OCI Labels

Every image MUST carry these labels:

| Label | Value |
|-------|-------|
| `org.opencontainers.image.title` | `cq-<kind>-<name>` |
| `org.opencontainers.image.description` | `CloudQuery <kind> plugin <name> <version>` |
| `org.opencontainers.image.version` | `<version>` |
| `io.cloudquery.plugin.kind` | `<kind>` |
| `io.cloudquery.plugin.name` | `<name>` |

## Backward Compatibility

**None.** The old `cloudquery-plugin-<name>` pattern is fully abandoned. No dual-publishing, no redirects, no aliases. Consumers MUST update their references.

## Files Governed by This Contract

| File | What it produces |
|------|-----------------|
| `scripts/build.sh` | Local image builds |
| `.github/actions/build-plugin/action.yaml` | CI image builds |
| `.github/workflows/publish.yaml` | Build metadata JSON with image reference |
| `Makefile` | Local smoke-test and clean targets |
| `examples/*/deployment.yaml` | K8s resource names, labels, image references |
| `examples/*/cloudquery.yaml` | gRPC endpoint paths |
| `examples/*/sync-job.yaml` | gRPC endpoint paths in sync jobs |
| `README.md` | Documentation examples |
