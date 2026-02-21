# Quickstart: Rename Destination Plugin OCI Images

**Feature**: 003-rename-dest-images  
**Date**: 2026-02-21

## What Changed

All OCI images published by this repository now follow the `cq-<kind>-<name>` naming convention instead of `cloudquery-plugin-<name>`.

| Plugin | Old Image | New Image |
|--------|-----------|-----------|
| S3 destination | `ghcr.io/infobloxopen/cloudquery-plugin-s3:v7.10.2` | `ghcr.io/infobloxopen/cq-destination-s3:v7.10.2` |
| PostgreSQL destination | `ghcr.io/infobloxopen/cloudquery-plugin-postgresql:v8.14.1` | `ghcr.io/infobloxopen/cq-destination-postgresql:v8.14.1` |
| File destination | `ghcr.io/infobloxopen/cloudquery-plugin-file:v5.5.1` | `ghcr.io/infobloxopen/cq-destination-file:v5.5.1` |

## For Consumers

Update any Kubernetes manifests, CloudQuery configs, or scripts that reference the old image names:

```yaml
# Old
image: ghcr.io/infobloxopen/cloudquery-plugin-s3:v7.10.2

# New
image: ghcr.io/infobloxopen/cq-destination-s3:v7.10.2
```

For gRPC sidecar paths in CloudQuery config:
```yaml
# Old
path: cloudquery-plugin-s3:7777

# New
path: cq-destination-s3:7777
```

## For Developers

### Building locally

No change to the build command:
```bash
make build PLUGIN=s3
```

The script now automatically reads the `kind` field from `plugins.yaml` and constructs `cq-destination-s3:<version>`.

### Running smoke tests

```bash
make smoke-test PLUGIN=s3
```

The Makefile automatically constructs the correct image name using the `kind` field.

### Adding a new plugin

Add an entry to `plugins.yaml` with the `kind` field:

```yaml
plugins:
  - name: xkcd
    kind: source        # This determines the image prefix: cq-source-xkcd
    version: v1.0.0
    upstream:
      repo: https://github.com/cloudquery/cloudquery
      tag: plugins-source-xkcd-v1.0.0
      commit: <sha>
    build:
      plugin_dir: plugins/source/xkcd
      go_version: "1.25.6"
```

The naming convention is automatic — `kind: source` → `cq-source-xkcd`, `kind: destination` → `cq-destination-<name>`.

## Verification

After the change, verify no old references remain:

```bash
# Should return zero results (excluding historical specs/ADRs)
grep -r "cloudquery-plugin-" --include="*.sh" --include="*.yaml" --include="*.md" \
  --exclude-dir=specs --exclude-dir=docs/adr .
```
