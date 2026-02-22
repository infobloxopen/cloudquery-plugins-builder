# Contract: Repository URL Convention

**Feature**: 004-use-fork-repo  
**Date**: 2026-02-22

## Purpose

Defines the convention for which repository URL to use when referencing CloudQuery plugin source code in this project.

## Convention

### Source Repository for Plugin Builds

All plugin image builds MUST use the Infoblox fork as the source repository:

```
https://github.com/infobloxopen/cloudquery
```

This URL is used in:
- `plugins.yaml` → `upstream.repo` field
- `Dockerfile` → `UPSTREAM_REPO` build argument default
- `README.md` → instructional examples and `git ls-remote` commands

### Original Upstream (Attribution Only)

The original upstream repository is:

```
https://github.com/cloudquery/cloudquery
```

This URL may still appear in:
- Go module paths (`ldflags_version_path`) — these are Go import paths, not git URLs
- Historical documentation and ADRs — for attribution and context
- Research documents — reflecting the state at the time of research
- CQ CLI image references (`ghcr.io/cloudquery/cloudquery:latest`) — different product

### Rules

1. **New plugin entries** in `plugins.yaml` MUST use `https://github.com/infobloxopen/cloudquery` as the `upstream.repo`.
2. **Documentation** instructing contributors to look up tags or resolve commits MUST reference the fork URL.
3. **Go module paths** (e.g., `github.com/cloudquery/cloudquery/plugins/destination/...`) MUST NOT be changed — they reflect the module declarations in the fork's source code.
4. **CQ CLI image references** (`ghcr.io/cloudquery/cloudquery:latest`) are out of scope — these reference a different product published by CloudQuery Inc.

### Verification

To verify a tag exists in the fork:
```bash
git ls-remote --tags https://github.com/infobloxopen/cloudquery <tag-name>
```

To verify the `plugins.yaml` convention:
```bash
yq '.plugins[].upstream.repo' plugins.yaml | sort -u
# Expected output: https://github.com/infobloxopen/cloudquery
```
