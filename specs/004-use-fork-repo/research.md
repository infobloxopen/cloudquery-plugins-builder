# Research: Use Infoblox Fork of CloudQuery

**Feature**: 004-use-fork-repo  
**Date**: 2026-02-22

## Fork Parity Verification

### Decision: Fork has full parity with upstream for all pinned versions

**Rationale**: The Infoblox fork at `https://github.com/infobloxopen/cloudquery` contains all three required plugin tags with identical commit SHAs. Switching the `upstream.repo` field is a safe, non-breaking change.

**Verification results**:

| Plugin | Tag | Upstream SHA | Fork SHA | Match |
|--------|-----|-------------|----------|-------|
| S3 v7.10.2 | `plugins-destination-s3-v7.10.2` | `090de0b96fa156618c2e1d0e00f75f4825340eb4` | `090de0b96fa156618c2e1d0e00f75f4825340eb4` | Identical |
| File v5.5.1 | `plugins-destination-file-v5.5.1` | `09c6e152c5335ab0157ed6da855b31e285539b3f` | `09c6e152c5335ab0157ed6da855b31e285539b3f` | Identical |
| PostgreSQL v8.14.1 | `plugins-destination-postgresql-v8.14.1` | `a5431aea2c8920890ea94de5abe7a485bd29e2f6` | `a5431aea2c8920890ea94de5abe7a485bd29e2f6` | Identical |

**Alternatives considered**:
- Keep upstream URL and use fork only selectively → Rejected: defeats the purpose of maintaining a fork; inconsistent configuration.
- Change Go module paths to match fork org → Rejected: fork source code retains `github.com/cloudquery/cloudquery` as the Go module path. Changing ldflags paths would break the build.

## Git URL vs Go Module Path Distinction

### Decision: Only change git clone URLs; preserve Go module paths

**Rationale**: The `upstream.repo` field is a git URL used in `git clone`. The `ldflags_version_path` values are Go import paths declared in the source code's `go.mod`. Even though both contain `github.com/cloudquery/cloudquery`, they serve completely different purposes. The fork's Go source still declares `module github.com/cloudquery/cloudquery/plugins/...` — this is standard for forks that don't intend to change import paths.

**Classification of all `cloudquery/cloudquery` references**:

| Classification | Count | Action |
|---|---|---|
| GIT_URL | 5 | MUST change to `infobloxopen/cloudquery` |
| GO_MODULE_PATH | 13 | Do NOT change |
| HISTORICAL/ATTRIBUTION | 11 | Preserve for context; add fork note where appropriate |
| SPEC_REFERENCE | 12 | Update to reflect fork |

## File Change Inventory

### Operational files (GIT_URL changes — MUST change)

| File | Line | Current | New |
|------|------|---------|-----|
| `Dockerfile` | L16 | `ARG UPSTREAM_REPO=https://github.com/cloudquery/cloudquery` | `ARG UPSTREAM_REPO=https://github.com/infobloxopen/cloudquery` |
| `plugins.yaml` | L7 | `repo: https://github.com/cloudquery/cloudquery` (s3) | `repo: https://github.com/infobloxopen/cloudquery` |
| `plugins.yaml` | L20 | `repo: https://github.com/cloudquery/cloudquery` (file) | `repo: https://github.com/infobloxopen/cloudquery` |
| `plugins.yaml` | L33 | `repo: https://github.com/cloudquery/cloudquery` (postgresql) | `repo: https://github.com/infobloxopen/cloudquery` |
| `README.md` | L95 | `repo: https://github.com/cloudquery/cloudquery` (example) | `repo: https://github.com/infobloxopen/cloudquery` |
| `README.md` | L109 | `git ls-remote https://github.com/cloudquery/cloudquery ...` | `git ls-remote https://github.com/infobloxopen/cloudquery ...` |

### Documentation files (update for accuracy)

| File | Action |
|------|--------|
| `README.md` L107 | Update monorepo link to fork; add note about original upstream |
| `docs/adr/001-monorepo-tag-checkout.md` | Add addendum noting migration to fork |

### Spec files (update references)

| File | Action |
|------|--------|
| `specs/001-oci-image-pipeline/data-model.md` | Update repo URL examples |
| `specs/001-oci-image-pipeline/plan.md` | Update repo URL examples |
| `specs/002-xkcd-source-plugin/spec.md` | Update repo URL references |
| `specs/003-rename-dest-images/quickstart.md` | Update repo URL examples |

### Files NOT changing (Go module paths / historical)

| File | Lines | Reason |
|------|-------|--------|
| `plugins.yaml` | L14, L27, L40 | Go module paths — fork retains original module declarations |
| `README.md` | L102 | Go module path in example |
| `specs/001-oci-image-pipeline/research.md` | L86-88, L182 | Go module paths |
| `specs/001-oci-image-pipeline/research.md` | L5, L28, L37, L244 | Historical research data — describes upstream as it was at research time |
| `specs/002-xkcd-source-plugin/spec.md` | L119 | Go module path |
| `examples/*/sync-job.yaml` | L10 | CQ CLI container image (`ghcr.io/cloudquery/cloudquery:latest`) — this is a different product (the CLI runner), not the plugin build source |

## Script Hardcoding Analysis

### Decision: No script changes needed

**Rationale**: Both `build.sh` and `validate-manifest.sh` read the `upstream.repo` value dynamically from `plugins.yaml` using `yq`. There are zero hardcoded references to the upstream URL in any script.

**Evidence**:
- `build.sh` L64: `UPSTREAM_REPO=$(yq ".plugins[${PLUGIN_INDEX}].upstream.repo" "$MANIFEST")`
- `validate-manifest.sh` L103: `REPO=$(yq ".plugins[$i].upstream.repo" "$MANIFEST")`

**Alternatives considered**:
- Add a script-level override/fallback URL → Rejected: unnecessary complexity; manifest is the source of truth.

## JSON Schema Analysis

### Decision: No schema changes needed

**Rationale**: The `plugins-manifest.schema.json` defines `upstream.repo` as `{ "type": "string", "format": "uri", "pattern": "^https://" }`. This accepts any HTTPS URL — it does not restrict to a specific domain or organization.

**Alternatives considered**:
- Restrict schema to only allow `infobloxopen/cloudquery` → Rejected: overly restrictive; the pipeline should work with any valid git repo URL.

## CQ CLI Image References

### Decision: Do NOT change `ghcr.io/cloudquery/cloudquery:latest` references

**Rationale**: The `examples/*/sync-job.yaml` files reference `ghcr.io/cloudquery/cloudquery:latest` — this is the CloudQuery **CLI** container image used to run syncs. It's a different product from the plugin source code. The CLI image is published by CloudQuery Inc. and is not part of the fork. Changing this reference is out of scope for this feature.

**Alternatives considered**:
- Build a custom CLI image from the fork → Rejected: out of scope; separate feature if needed.
- Point to an Infoblox-published CLI image → Rejected: no such image exists currently.
