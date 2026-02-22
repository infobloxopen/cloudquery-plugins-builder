# Implementation Plan: Build All Destination Plugins with Automated Daily Updates

**Branch**: `005-auto-update-dest-plugins` | **Date**: 2026-02-22 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/005-auto-update-dest-plugins/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Expand `plugins.yaml` from 3 destination plugins to all Go-based destination plugins (~20+) available in the Infoblox fork, and create automated CI workflows to: (1) detect and apply new plugin release tags daily, (2) update Go versions weekly to the latest stable release ≥2 weeks old, and (3) support per-plugin CGO opt-in via a `build.cgo_required` manifest field while keeping fully static distroless images as the default. All Docker image tags include a git suffix from this repository for traceability.

## Technical Context

**Language/Version**: Bash (update/detection scripts); Go 1.25.6 (existing entrypoint — unchanged); YAML (manifest, CI workflows)
**Primary Dependencies**: yq, jq, git (ls-remote), Docker Buildx, GitHub Actions, curl (Go version API)
**Storage**: N/A (images in GHCR; manifest in-repo; build index as JSON artifact)
**Testing**: `make validate` (JSON Schema + upstream ref verification); `make smoke-test` (TCP port check); shellcheck
**Target Platform**: GitHub Actions runners (ubuntu-latest); Docker images (linux/amd64, linux/arm64)
**Project Type**: Single project (CI pipeline + helper scripts)
**Performance Goals**: Update script completes full check of 20+ plugins in under 2 minutes (SC-003); full build matrix completes within 60 minutes on GHA
**Constraints**: No proprietary binaries; CGO support is exception-only (per-plugin opt-in); all actions pinned to SHA; auto-commits to main require appropriate token permissions
**Scale/Scope**: 20+ destination plugins; daily update schedule; weekly Go version update; all driven by `plugins.yaml`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Article | Status | Evidence |
|---------|--------|----------|
| **I. Licensing & Redistribution** | ✅ PASS | All plugins built from Infoblox fork (Apache-2.0/MPL-2.0 upstream); LICENSE files copied into images at `/licenses/`; no proprietary binaries |
| **II. Reproducibility & Provenance** | ✅ PASS | Manifest pins upstream git tag + commit SHA for every plugin; git suffix in image tag traces back to this repo's exact build; Dockerfile pins Go version and base image |
| **III. Supply Chain Security** | ✅ PASS | Existing SBOM/provenance/cosign from feature 001 applies to all new plugins; CGO-enabled images still use distroless (no shell); non-root UID |
| **IV. K8s Runtime Contract** | ✅ PASS | Same Dockerfile + entrypoint wrapper; gRPC on `[::]:7777`; env var overrides; read-only rootfs; all caps dropped |
| **V. Manifest-Driven & Scalable** | ✅ PASS | All 20+ plugins in `plugins.yaml`; CI matrix generated dynamically; adding a plugin = one YAML block; update script reads manifest |
| **VI. Transparency & Trackability** | ✅ PASS | Build index covers all plugins; update commits list what changed; git suffix provides image-to-build traceability |
| **VII. Quality Gates** | ✅ PASS | validate → build → smoke-test → push pipeline unchanged; auto-update validates before committing; failures block commit |
| **Coding: GitHub Actions** | ✅ PASS | New workflows pin actions to SHA; permissions set per job; cron schedule for daily/weekly; reusable patterns from feature 001 |
| **Coding: Bash** | ✅ PASS | All new scripts: `set -euo pipefail`, shellcheck, <200 lines, `#!/usr/bin/env bash` |
| **Coding: Docs** | ✅ PASS | README updated with expanded plugin list; ADRs for CGO opt-in and auto-update decisions |

**Gate result**: ✅ ALL PASS — no violations.

## Project Structure

### Documentation (this feature)

```text
specs/005-auto-update-dest-plugins/
├── plan.md              # This file
├── research.md          # Phase 0 output — CGO analysis, Go version API, auto-commit strategy
├── data-model.md        # Phase 1 output — expanded manifest schema, update script data flow
├── quickstart.md        # Phase 1 output — adding plugins, running updates, CGO opt-in
├── contracts/
│   ├── update-script.md           # Contract for update-plugins.sh behaviour
│   ├── go-version-update.md       # Contract for weekly Go version update workflow
│   └── naming-convention.md       # Image tagging convention with git suffix
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (changes to repository root)

```text
cloudquery-plugins-builder/
├── plugins.yaml                          # MODIFIED: 3 → 20+ destination plugin entries
├── Dockerfile                            # MODIFIED: conditional CGO support via build arg
├── Makefile                              # UNCHANGED (already dynamic)
│
├── schemas/
│   └── plugins-manifest.schema.json      # MODIFIED: add cgo_required field to build schema
│
├── scripts/
│   ├── build.sh                          # MODIFIED: read cgo_required, set CGO_ENABLED + base image; add git suffix to tag
│   ├── update-plugins.sh                 # NEW: detect + apply new plugin versions from fork
│   ├── update-go-version.sh              # NEW: update go_version to latest stable Go ≥2 weeks old
│   └── detect-new-plugins.sh             # NEW: find new destination plugins not in manifest
│
├── .github/
│   └── workflows/
│       ├── update-plugins.yaml           # NEW: daily scheduled workflow for plugin version updates
│       └── update-go-version.yaml        # NEW: weekly scheduled workflow for Go version updates
│
└── docs/
    └── adr/
        ├── 005-cgo-exception-basis.md    # NEW: ADR for per-plugin CGO opt-in
        └── 006-auto-update-pipeline.md   # NEW: ADR for auto-update architecture
```

**Structure Decision**: No new directories. Extends existing structure with new scripts and workflows. The manifest, Dockerfile, and build script are modified in-place. New CI workflows follow the same `.github/workflows/` convention planned in feature 001.

## Build Pipeline Changes

### Dockerfile CGO Support

```text
                        ┌──────────────────┐
                        │  cgo_required?   │
                        └────┬────────┬────┘
                             │ false  │ true
                             ▼        ▼
                     CGO_ENABLED=0  CGO_ENABLED=1
                             │        │
                             ▼        ▼
              distroless/    distroless/
              static-debian12  base-debian12
              :nonroot         :nonroot
```

A new build arg `CGO_ENABLED` (default `0`) and `BASE_IMAGE` (default `gcr.io/distroless/static-debian12:nonroot`) are set by `build.sh` based on the manifest's `build.cgo_required` field.

### Image Tagging with Git Suffix

```text
Image tag format:  <upstream-version>-<git-suffix>
Example:           v8.14.1-g1a2b3c4

Full image ref:    ghcr.io/infobloxopen/cq-destination-postgresql:v8.14.1-g1a2b3c4

Where:
  - v8.14.1    = upstream plugin version from plugins.yaml
  - g1a2b3c4   = git describe --always from this repository
  - cq-        = prefix indicating upstream CloudQuery origin
```

### Update Script Flow

```text
┌─────────────────────────┐
│  update-plugins.sh      │
│  [--dry-run]            │
└───────────┬─────────────┘
            │
            ▼  (for each plugin in plugins.yaml)
┌─────────────────────────┐
│  git ls-remote --tags   │  Query fork for plugins-destination-<name>-v*
│  <fork-url>             │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  Filter stable versions │  Regex: ^plugins-destination-<name>-v\d+\.\d+\.\d+$
│  Sort by semver         │  Pick latest
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  Compare with current   │  If latest > current → update
│  version in manifest    │  If latest ≤ current → skip
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐   ┌─────────────────────────┐
│  Update plugins.yaml    │   │  Detect new plugins     │
│  (version, tag, commit, │   │  (tags not in manifest) │
│   ldflags if major bump)│   │  → log for review       │
└───────────┬─────────────┘   └─────────────────────────┘
            │
            ▼
┌─────────────────────────┐
│  make validate          │  Verify updated manifest
└───────────┬─────────────┘
            │
            ▼  (if not --dry-run and in CI)
┌─────────────────────────┐
│  git commit + push      │  Descriptive commit message
└─────────────────────────┘
```

### Weekly Go Version Update Flow

```text
┌─────────────────────────┐
│  update-go-version.sh   │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  curl go.dev/dl/?mode=  │  Fetch all stable Go releases as JSON
│  json                   │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  Filter: stable=true &  │  Latest release with release date ≥ 14 days ago
│  age ≥ 14 days          │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  Compare with current   │  If newer → update all go_version fields
│  go_version fields      │  If same or older → no-op
└───────────┬─────────────┘
            │
            ▼  (if changed, on main)
┌─────────────────────────┐
│  yq update + validate   │
│  git commit + push      │
└─────────────────────────┘
```

## Milestones

### Milestone 1: Expand Manifest (US1)

| Deliverable | Priority |
|------------|----------|
| Add all 20+ destination plugins to `plugins.yaml` with correct tags/commits | P1 |
| Add `build.cgo_required` field to JSON Schema | P1 |
| Update Dockerfile to support CGO via build args | P1 |
| Update `build.sh` to read `cgo_required` and set build args | P1 |
| Update `build.sh` to append git suffix to image tag | P1 |
| Verify all plugins build successfully with `make build-all` | P1 |
| ADR for CGO exception basis | P2 |

### Milestone 2: Auto-Update Pipeline (US2, US3, US4)

| Deliverable | Priority |
|------------|----------|
| `scripts/update-plugins.sh` (detect + apply new versions) | P1 |
| `scripts/detect-new-plugins.sh` (find new plugins in fork) | P1 |
| `.github/workflows/update-plugins.yaml` (daily cron) | P1 |
| Dry-run mode for update script | P2 |
| Update commit message formatting | P2 |

### Milestone 3: Go Version Automation (US5)

| Deliverable | Priority |
|------------|----------|
| `scripts/update-go-version.sh` (weekly Go update) | P2 |
| `.github/workflows/update-go-version.yaml` (weekly cron, main-only) | P2 |

### Milestone 4: Documentation & Polish

| Deliverable | Priority |
|------------|----------|
| ADR for auto-update architecture | P2 |
| Updated README with expanded plugin list | P2 |
| Updated quickstart guide | P2 |

## Complexity Tracking

> No constitution violations to justify — all gates pass.
