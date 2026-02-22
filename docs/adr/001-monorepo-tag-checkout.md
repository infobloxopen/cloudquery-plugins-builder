# ADR 001: Build from Upstream Monorepo Tags

**Date**: 2026-02-12
**Status**: Accepted
**Decision**: D1 — Monorepo Tag Checkout

## Context

CloudQuery plugins live in a monorepo at `github.com/cloudquery/cloudquery`. Each plugin is released via tags following the pattern `plugins-destination-<name>-v<version>`. We need a strategy to check out and build individual plugin source code from this monorepo.

## Decision

We build from upstream monorepo tags using `git clone --depth=1 --branch=<tag>`. The full monorepo is cloned at the exact tag, and the Dockerfile's `WORKDIR` is set to the plugin's subdirectory.

## Alternatives Considered

### 1. Sparse checkout (git sparse-checkout)
- **Pros**: Downloads only the plugin directory, saving bandwidth
- **Cons**: Requires multiple git commands, more complex Dockerfile, and the Go build may need files outside the sparse checkout (shared packages, go.work)
- **Rejected**: Complexity outweighs bandwidth savings; shallow clone is already fast

### 2. Download release tarball
- **Pros**: Simpler URL, no git dependency
- **Cons**: GitHub release tarballs don't exist per-plugin for monorepos; only per-tag tarballs exist which include the full repo anyway
- **Rejected**: No advantage over git clone

### 3. Fork and extract individual plugins
- **Pros**: Cleaner per-plugin repos
- **Cons**: Maintenance burden, drift from upstream, manual sync required
- **Rejected**: Violates the manifest-driven, low-maintenance design principle

## Consequences

- **Positive**: Simple, reproducible, exact tag pinning, works with any Go module structure
- **Positive**: Shallow clone (`--depth=1`) minimises download size
- **Negative**: Downloads full monorepo tree at the tag (~100MB), but this happens in a disposable Docker build stage
- **Mitigation**: Docker layer caching in CI reduces repeated downloads for unchanged tags

## Addendum: Migration to Infoblox Fork (2026-02-22)

**Context**: Infoblox now maintains a fork of the CloudQuery monorepo at `https://github.com/infobloxopen/cloudquery`. All image builds have been migrated to use the fork as the source repository instead of the upstream `https://github.com/cloudquery/cloudquery`.

**Impact on this ADR**: The original decision (D1 — Monorepo Tag Checkout) remains fully valid. The fork retains the same monorepo structure, tag naming convention, and commit SHAs. The only change is the git clone URL passed to `git clone --depth=1 --branch=<tag>`.

**What changed**:
- `plugins.yaml` `upstream.repo` fields → `https://github.com/infobloxopen/cloudquery`
- `Dockerfile` `UPSTREAM_REPO` default → `https://github.com/infobloxopen/cloudquery`

**What did NOT change**:
- Tag checkout strategy (still `git clone --depth=1 --branch=<tag>`)
- Go module paths (`ldflags_version_path`) — the fork's source code retains `github.com/cloudquery/cloudquery` as the Go module path
- Build process, Dockerfile structure, or validation logic

See [spec 004](../../specs/004-use-fork-repo/spec.md) for full details.
