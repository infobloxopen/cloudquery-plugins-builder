# Quickstart: Migrating to the Infoblox CloudQuery Fork

**Feature**: 004-use-fork-repo  
**Date**: 2026-02-22

## Overview

This guide walks through switching the CloudQuery plugins builder from the upstream repository to the Infoblox fork. The migration affects configuration and documentation only — no code logic changes.

## Prerequisites

- Git CLI installed
- Access to `https://github.com/infobloxopen/cloudquery` (the fork)
- `yq` installed (for YAML processing)

## Step-by-Step Migration

### Step 1: Verify fork parity

Before changing anything, confirm the fork has the tags you need:

```bash
# For each plugin in plugins.yaml, verify the tag exists in the fork
yq '.plugins[] | .upstream.tag' plugins.yaml | while read -r tag; do
  echo -n "Checking $tag... "
  git ls-remote --tags https://github.com/infobloxopen/cloudquery "$tag" | head -1 && echo "✓" || echo "MISSING"
done
```

### Step 2: Update `plugins.yaml`

Change the `upstream.repo` field for every plugin entry:

```yaml
# Before
upstream:
  repo: https://github.com/cloudquery/cloudquery
  tag: plugins-destination-postgresql-v8.14.1
  commit: a5431aea2c8920890ea94de5abe7a485bd29e2f6

# After
upstream:
  repo: https://github.com/infobloxopen/cloudquery
  tag: plugins-destination-postgresql-v8.14.1    # unchanged
  commit: a5431aea2c8920890ea94de5abe7a485bd29e2f6  # unchanged (same SHA in fork)
```

**Important**: Do NOT change `ldflags_version_path` values — they are Go module paths, not git URLs.

### Step 3: Update `Dockerfile`

Change the default value of the `UPSTREAM_REPO` build argument:

```dockerfile
# Before
ARG UPSTREAM_REPO=https://github.com/cloudquery/cloudquery

# After
ARG UPSTREAM_REPO=https://github.com/infobloxopen/cloudquery
```

### Step 4: Update `README.md`

Update all instructional references:
- Manifest example block: change `repo:` URL
- "Adding a new plugin" section: change `git ls-remote` URL and monorepo link
- Add attribution note for the original upstream

### Step 5: Update documentation

Update ADR 001 and spec files that reference the upstream URL in manifest/instruction contexts.

### Step 6: Validate

```bash
# Schema + upstream ref verification
make validate

# Build a plugin to confirm it clones from the fork
make build PLUGIN=postgresql

# Run smoke test
make smoke-test PLUGIN=postgresql
```

### Step 7: Verify no stale git-URL references

```bash
# Should return ZERO matches in operational files (Go module paths are expected)
grep -rn 'https://github.com/cloudquery/cloudquery' Dockerfile plugins.yaml scripts/
# Expected: no output
```

## What NOT to Change

| Item | Why |
|------|-----|
| `ldflags_version_path` values (e.g., `github.com/cloudquery/cloudquery/plugins/...`) | These are Go module import paths embedded in the fork's source code. Changing them breaks the build. |
| `upstream.tag` and `upstream.commit` values | The fork has the same tags and SHAs — these remain valid. |
| `examples/*/sync-job.yaml` image references (`ghcr.io/cloudquery/cloudquery:latest`) | This is the CQ CLI image, a different product. Out of scope. |
| `build.sh` and `validate-manifest.sh` | These scripts read the repo URL dynamically from the manifest. No code changes needed. |
| JSON schema (`plugins-manifest.schema.json`) | Already accepts any HTTPS URL. No restriction needed. |

## Adding a New Plugin (Post-Migration)

After migration, use the fork URL when adding new plugins:

```bash
# 1. Find the tag in the fork
git ls-remote --tags https://github.com/infobloxopen/cloudquery | grep "plugins-destination-mysql"

# 2. Get the commit SHA
git ls-remote https://github.com/infobloxopen/cloudquery plugins-destination-mysql-v3.2.0

# 3. Add entry to plugins.yaml with the fork URL
# upstream:
#   repo: https://github.com/infobloxopen/cloudquery
#   tag: plugins-destination-mysql-v3.2.0
#   commit: <sha-from-step-2>
```
