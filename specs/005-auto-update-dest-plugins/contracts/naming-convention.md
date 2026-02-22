# Contract: Image Naming & Tagging Convention

**Feature**: 005-auto-update-dest-plugins

## Image Name Format

```text
ghcr.io/infobloxopen/cq-<kind>-<name>:<version>-<git-suffix>
```

### Components

| Component | Source | Example |
|-----------|--------|---------|
| `ghcr.io/infobloxopen` | Fixed registry + org | — |
| `cq-` | Prefix indicating upstream CloudQuery origin | — |
| `<kind>` | `plugins[].kind` | `destination` |
| `<name>` | `plugins[].name` | `postgresql` |
| `<version>` | `plugins[].version` | `v8.14.1` |
| `<git-suffix>` | `git describe --always` from this repo | `g1a2b3c4` |

### Examples

| Plugin | Version | Git Suffix | Full Image Reference |
|--------|---------|------------|---------------------|
| postgresql | v8.14.1 | g1a2b3c4 | `ghcr.io/infobloxopen/cq-destination-postgresql:v8.14.1-g1a2b3c4` |
| s3 | v7.10.2 | g1a2b3c4 | `ghcr.io/infobloxopen/cq-destination-s3:v7.10.2-g1a2b3c4` |
| sqlite | v2.14.1 | g1a2b3c4 | `ghcr.io/infobloxopen/cq-destination-sqlite:v2.14.1-g1a2b3c4` |
| test | v2.8.30 | g1a2b3c4 | `ghcr.io/infobloxopen/cq-destination-test:v2.8.30-g1a2b3c4` (not pushed) |

## Git Suffix Generation

```bash
GIT_SUFFIX=$(git describe --always --dirty 2>/dev/null || echo "unknown")
IMAGE_TAG="${VERSION}-${GIT_SUFFIX}"
```

Behaviour:
- **Tagged commit**: `v0.5.0` → image tag: `v8.14.1-v0.5.0`
- **N commits after tag**: `v0.5.0-3-g1a2b3c4` → image tag: `v8.14.1-v0.5.0-3-g1a2b3c4`
- **No tags in repo**: `g1a2b3c4` → image tag: `v8.14.1-g1a2b3c4`
- **Dirty working tree** (local only): `g1a2b3c4-dirty` → image tag: `v8.14.1-g1a2b3c4-dirty`

## Rationale

1. **Traceability**: The git suffix maps an image to the exact state of this build repo (Dockerfile, entrypoint, scripts), not just the upstream plugin version
2. **Rebuild distinction**: If the Dockerfile or entrypoint changes, rebuilding the same upstream plugin version produces a distinct tag
3. **`cq-` prefix**: Identifies the image as built from CloudQuery upstream source (per user requirement: "the cq prefix means that it comes from the upstream cloudquery repo")
4. **No `latest` tag**: Enforces explicit version pinning per Constitution Article II

## Impact on Existing Scripts

### `scripts/build.sh`

Current tag generation:
```bash
IMAGE_NAME="${IMAGE_ORG}/cq-${KIND}-${PLUGIN_NAME}:${VERSION}"
```

Updated tag generation:
```bash
GIT_SUFFIX=$(git describe --always --dirty 2>/dev/null || echo "unknown")
IMAGE_NAME="${IMAGE_ORG}/cq-${KIND}-${PLUGIN_NAME}:${VERSION}-${GIT_SUFFIX}"
```

### `Makefile` smoke-test targets

Smoke test targets construct the image name from the manifest. They must also append the git suffix when looking up the built image.

### Build index

The `build-index.json` and `docs/build-index.md` entries include the full image tag with git suffix.

## Compatibility

- Kubernetes deployments that pin image tags will need to use the full tag including git suffix
- The git suffix is stable for a given commit of this repo — all plugins built from the same commit share the same suffix
- Container registries handle the extended tag format without issues
