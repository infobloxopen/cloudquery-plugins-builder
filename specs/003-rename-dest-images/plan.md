# Implementation Plan: Rename Destination Plugin OCI Images

**Branch**: `003-rename-dest-images` | **Date**: 2026-02-21 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/003-rename-dest-images/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Rename all published OCI images from `cloudquery-plugin-<name>` to `cq-{kind}-<name>` (e.g., `cq-destination-s3`, `cq-source-xkcd`). The `kind` field already exists in `plugins.yaml` and is already propagated through the CI matrix and build action; it is simply not used in image name construction. This is a find-and-replace across 4 functional files (build script, CI action, publish workflow, Makefile) and 11 content files (README, examples, smoke-test comment).

## Technical Context

**Language/Version**: Bash (scripts), GitHub Actions YAML (CI), Make (build targets), Go 1.25+ (entrypoint — unchanged)
**Primary Dependencies**: `yq` (YAML processing), Docker Buildx, `cosign`, GitHub Actions (`docker/build-push-action`)
**Storage**: N/A — no data persistence; OCI images are pushed to GHCR
**Testing**: Smoke tests via `scripts/smoke-test.sh` (container start + gRPC port check); manifest validation via JSON Schema
**Target Platform**: GitHub Actions runners (Ubuntu), developer machines (macOS/Linux) for local builds
**Project Type**: Single project — CI/CD pipeline scripts and configuration
**Performance Goals**: N/A — build-time change only, no runtime impact
**Constraints**: Images must be pushed to `ghcr.io/infobloxopen/` namespace; no backward-compatibility aliases (FR-010)
**Scale/Scope**: 3 destination plugins currently; naming pattern must work for N source + M destination plugins

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Constitution Article | Relevant? | Status | Notes |
|---|---------------------|-----------|--------|-------|
| I | Licensing & Redistribution | No | PASS | No licensing change — same upstream code, different image name |
| II | Reproducibility & Provenance | Yes | PASS | OCI labels are updated to use new name; all provenance labels (`upstream-repo`, `upstream-tag`, `upstream-commit`) are unchanged |
| III | Supply Chain Security | No | PASS | SBOM, SLSA, cosign signing unchanged — they operate on the final image regardless of name |
| IV | Kubernetes-First Runtime | No | PASS | Entrypoint, port, runtime contract unchanged; only image reference changes |
| V | Manifest-Driven & Scalable | Yes | PASS | `plugins.yaml` remains the single source of truth; `kind` field drives the image name prefix; no per-plugin workflow files introduced |
| VI | Transparency & Trackability | Yes | PASS | Build index records will use new image names; human-readable docs updated |
| VII | Quality Gates | Yes | PASS | Manifest validation (JSON Schema) unchanged; smoke test updated to use new image refs; push gating unchanged |
| — | Bash Conventions | Yes | PASS | `build.sh` already uses `set -euo pipefail`; change adds `kind` validation (2 lines) |
| — | GitHub Actions YAML | Yes | PASS | Actions already pinned to SHA; `kind` input already exists in composite action |
| — | Documentation | Yes | PASS | README, examples updated; ADR recommended for the naming migration decision |

**Gate result**: ✅ PASS — no violations. Proceed to Phase 0.

## Project Structure

### Documentation (this feature)

```text
specs/003-rename-dest-images/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output (image naming model)
├── quickstart.md        # Phase 1 output (developer instructions)
├── contracts/           # Phase 1 output (naming convention contract)
│   └── naming-convention.md
└── tasks.md             # Phase 2 output (NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
# Files requiring FUNCTIONAL changes (image name construction logic):
scripts/build.sh                            # L68: IMAGE_NAME formula; L102: OCI title label
.github/actions/build-plugin/action.yaml    # L69: IMAGE formula; L113: OCI title label
.github/workflows/publish.yaml              # L107: build metadata image field
Makefile                                    # L46, L54, L98: image refs (needs yq for kind)

# Files requiring CONTENT updates (references to old name):
README.md                                   # L117-123, L151: naming docs & examples
examples/file/deployment.yaml               # All K8s labels + image ref
examples/file/cloudquery.yaml               # gRPC path
examples/file/sync-job.yaml                 # gRPC path
examples/s3/deployment.yaml                 # All K8s labels + image ref
examples/s3/cloudquery.yaml                 # gRPC path
examples/s3/sync-job.yaml                   # gRPC path
examples/postgresql/deployment.yaml         # All K8s labels + image ref
examples/postgresql/cloudquery.yaml         # gRPC path
examples/postgresql/sync-job.yaml           # gRPC path
scripts/smoke-test.sh                       # L7: comment example

# Files NOT requiring changes:
scripts/generate-matrix.sh                  # Already emits `kind` in matrix JSON
scripts/validate-manifest.sh                # No image name references
scripts/generate-build-index.sh             # Consumes build metadata; no hardcoded names
Dockerfile                                  # No image name references
cmd/entrypoint/main.go                      # Runtime only; no image naming
plugins.yaml                                # Already has `kind` field; no image name refs
```

**Structure Decision**: No new files or directories are created in the source tree. This is purely an edit-in-place refactor across existing scripts, workflows, and documentation.

## Complexity Tracking

> No constitution violations — section intentionally left empty.
