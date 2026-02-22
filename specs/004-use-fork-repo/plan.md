# Implementation Plan: Use Infoblox Fork of CloudQuery for Image Builds

**Branch**: `004-use-fork-repo` | **Date**: 2026-02-22 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/004-use-fork-repo/spec.md`

## Summary

Switch all image-build and manifest references from the upstream CloudQuery monorepo (`https://github.com/cloudquery/cloudquery`) to the Infoblox-maintained fork (`https://github.com/infobloxopen/cloudquery`). This is a configuration and documentation change only — no code logic changes are needed. The fork has verified identical tags and commit SHAs for all currently pinned plugin versions, making this a safe, non-breaking migration. Go module import paths (`ldflags_version_path`) must NOT change because they are embedded in the fork's source code.

## Technical Context

**Language/Version**: Bash scripts, Dockerfile (multi-stage), YAML manifests — no application code changes  
**Primary Dependencies**: Docker Buildx, yq, jq, git (all pre-existing; no new dependencies)  
**Storage**: N/A  
**Testing**: `make validate` (JSON Schema + upstream ref verification), `make build PLUGIN=<name>` (image build), `make smoke-test` (gRPC port check)  
**Target Platform**: OCI images (linux/amd64, linux/arm64) deployed on Kubernetes  
**Project Type**: Configuration/documentation migration within existing pipeline  
**Performance Goals**: N/A — no runtime performance impact  
**Constraints**: Fork must contain all pinned tags with matching commit SHAs; Go module paths must not be altered  
**Scale/Scope**: 5 GIT_URL references across 3 operational files (Dockerfile, plugins.yaml, README.md) + documentation updates across ~6 additional files (ADR, specs)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Status | Notes |
|---|-----------|--------|-------|
| I | Licensing & Redistribution Compliance | **PASS** | Fork contains the same MPL-2.0 licensed open-source code. Images still carry upstream license at `/licenses/`. No proprietary sources introduced. |
| II | Reproducibility & Provenance | **PASS** | Same tags and commit SHAs. OCI labels (`io.cloudquery.plugin.upstream-repo`) will correctly reflect the fork URL. Provenance chain is preserved. |
| III | Supply Chain Security | **PASS** | No changes to SBOM, provenance, cosign signing, or base images. Fork is under Infoblox organizational control — strictly better from a supply-chain perspective. |
| IV | Kubernetes-First Runtime Contract | **PASS** | No changes to entrypoint, gRPC binding, ports, or runtime behavior. |
| V | Manifest-Driven & Scalable | **PASS** | `plugins.yaml` remains the single source of truth. Only `upstream.repo` values change. No per-plugin workflow changes. |
| VI | Transparency & Trackability | **PASS** | Build index will reflect the fork URL in `upstream_repo` — correct and intentional. |
| VII | Quality Gates | **PASS** | `validate-manifest.sh` reads repo URL dynamically from manifest — no hardcoded URLs. All validation gates continue to function unchanged. |

**Gate result**: ALL PASS — no violations. Proceed to Phase 0.

## Project Structure

### Documentation (this feature)

```text
specs/004-use-fork-repo/
├── plan.md              # This file
├── research.md          # Phase 0: fork parity verification + file inventory
├── data-model.md        # Phase 1: change map (which fields in which files)
├── quickstart.md        # Phase 1: step-by-step migration guide
├── contracts/
│   └── repo-convention.md  # Phase 1: URL convention contract
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
# Files modified by this feature (no new source files created):
Dockerfile                              # L16: ARG UPSTREAM_REPO default value
plugins.yaml                            # L7, L20, L33: upstream.repo per plugin
README.md                               # L95, L107, L109: examples + instructions
docs/adr/001-monorepo-tag-checkout.md   # Addendum noting fork migration
specs/001-oci-image-pipeline/           # data-model.md, plan.md repo URL examples
specs/002-xkcd-source-plugin/spec.md    # Repo URL references
specs/003-rename-dest-images/quickstart.md  # Repo URL examples
```

**Structure Decision**: No new source directories or files at the repository root. This feature exclusively modifies existing configuration and documentation files.

## Complexity Tracking

No constitution violations — this section is intentionally empty.
