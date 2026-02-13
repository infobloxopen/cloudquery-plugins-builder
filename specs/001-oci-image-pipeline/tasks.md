# Tasks: OCI Image Pipeline for CloudQuery Plugins

**Input**: Design documents from `/specs/001-oci-image-pipeline/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Tests**: Not explicitly requested — test tasks are omitted. Smoke tests are part of the build pipeline itself (scripts/smoke-test.sh).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Project type**: Single project (CI pipeline + helper scripts + examples)
- All paths are relative to repository root `cloudquery-plugins-builder/`
- Go module lives at `cmd/entrypoint/` (entrypoint wrapper only)
- No `src/` directory — primary artifacts are Dockerfile, CI workflows, Bash scripts, and K8s examples

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the project skeleton and initialise tooling

- [x] T001 Create project directory structure with folders: `schemas/`, `cmd/entrypoint/`, `scripts/`, `.github/workflows/`, `.github/actions/build-plugin/`, `examples/postgresql/`, `examples/s3/`, `examples/file/`, `docs/adr/`
- [x] T002 [P] Create LICENSE file at LICENSE (same license as this repository)
- [x] T003 [P] Initialise Go module for the entrypoint wrapper at cmd/entrypoint/go.mod (module `github.com/infobloxopen/cloudquery-plugins-builder/cmd/entrypoint`, Go 1.25.6)
- [x] T004 [P] Create .gitignore with Go build artifacts, Docker build cache, OS files, and editor files at .gitignore

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core artifacts that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T005 Create plugins.yaml manifest at plugins.yaml listing 3 MVP destination plugins (s3 v7.10.2, file v5.5.1, postgresql v8.14.1) with full upstream repo/tag/commit and build args per the example in plan.md § Example Manifest
- [x] T006 [P] Create JSON Schema for plugin manifest at schemas/plugins-manifest.schema.json (copy from specs/001-oci-image-pipeline/contracts/plugins-manifest.schema.json and adjust `$id` to match repo path)
- [x] T007 [P] Create JSON Schema for build index at schemas/build-index.schema.json (copy from specs/001-oci-image-pipeline/contracts/build-index.schema.json and adjust `$id`)
- [x] T008 Create generic multi-stage Dockerfile at Dockerfile per plan.md § Dockerfile Design — Stage 1: plugin-builder (clone upstream at tag, `CGO_ENABLED=0 go build`), Stage 2: entrypoint-builder (build Go wrapper), Stage 3: distroless final image with OCI labels
- [x] T009 Create Go entrypoint wrapper at cmd/entrypoint/main.go per contracts/runtime-contract.md — read `CQ_PLUGIN_ADDRESS` (default `[::]`) and `CQ_PLUGIN_PORT` (default `7777`), construct `--address <addr>:<port>`, exec `/plugin` with args
- [x] T010 [P] Create manifest validation script at scripts/validate-manifest.sh — validate plugins.yaml against JSON Schema using `ajv` or `check-jsonschema`, then for each plugin verify upstream tag exists via `git ls-remote` and commit SHA matches
- [x] T011 [P] Create GHA matrix generation script at scripts/generate-matrix.sh — parse plugins.yaml with `yq`/`jq` to produce GitHub Actions matrix JSON (`{"include": [...]}`) per contracts/ci-workflows.md § Matrix Generation
- [x] T012 [P] Create smoke test script at scripts/smoke-test.sh — run container in background, wait up to 30s for TCP connection on port 7777, capture logs, report pass/fail, clean up container
- [x] T013 Create single-plugin local build script at scripts/build.sh — accept plugin name as argument, extract its entry from plugins.yaml, invoke `docker buildx build` with correct build args, tag image per naming convention `ghcr.io/infobloxopen/cloudquery-plugin-<name>:<version>`
- [x] T014 Create composite GHA action for building one plugin at .github/actions/build-plugin/action.yaml — inputs: plugin name, kind, version, upstream tag, build args; steps: setup Docker Buildx + QEMU, build multi-arch image (`linux/amd64`, `linux/arm64`), optionally push to GHCR, run smoke test, sign with cosign if pushing; outputs: image ref, digest

**Checkpoint**: All foundational artifacts ready — user story implementation can now begin

---

## Phase 3: User Story 1 — Operator Pins Plugin Versions → GHCR Images (Priority: P1) 🎯 MVP

**Goal**: An operator defines plugins and versions in `plugins.yaml`, pushes to `main`, and CI automatically builds and publishes multi-arch OCI images to GHCR with SBOM, provenance, and cosign signatures.

**Independent Test**: Edit `plugins.yaml` to list a single plugin/version, push to `main`, and confirm the tagged image appears in GHCR with correct OCI labels and multi-arch support.

### Implementation for User Story 1

- [x] T015 [US1] Create main-branch publish workflow at .github/workflows/publish.yaml per contracts/ci-workflows.md § Workflow 2 — trigger on push to `main` when `plugins.yaml` changes; permissions: `contents: write`, `packages: write`, `id-token: write`; steps: validate manifest, generate matrix, invoke composite action per matrix entry with push enabled, cosign keyless signing via OIDC; pin all third-party actions to full commit SHAs
- [x] T016 [P] [US1] Create local build-all script at scripts/build-all.sh — iterate over all plugins in plugins.yaml, call scripts/build.sh for each, report summary of successes/failures

**Checkpoint**: At this point, User Story 1 should be fully functional — pushing manifest changes to `main` publishes signed multi-arch images to GHCR

---

## Phase 4: User Story 2 — Platform Engineer Deploys Plugin Images to Kubernetes (Priority: P2)

**Goal**: A platform engineer pulls published images and deploys them to Kubernetes as gRPC servers, connecting CloudQuery sync jobs via `registry: grpc` without any Hub authentication.

**Independent Test**: Deploy the postgresql plugin image to a Kubernetes cluster (or Kind), verify the gRPC port is reachable from a CloudQuery job pod, and run a minimal sync.

### Implementation for User Story 2

- [x] T017 [P] [US2] Create postgresql K8s examples at examples/postgresql/deployment.yaml (Deployment + Service with security context, health probes, emptyDir for /tmp), examples/postgresql/sync-job.yaml (CQ sync Job), and examples/postgresql/cloudquery.yaml (CQ config with `registry: grpc`, `path: cloudquery-plugin-postgresql:7777`) per plan.md § Kubernetes Examples
- [x] T018 [P] [US2] Create s3 K8s examples at examples/s3/deployment.yaml, examples/s3/sync-job.yaml, and examples/s3/cloudquery.yaml — same structure as postgresql adapted for s3 plugin (`ghcr.io/infobloxopen/cloudquery-plugin-s3:v7.10.2`)
- [x] T019 [P] [US2] Create file K8s examples at examples/file/deployment.yaml, examples/file/sync-job.yaml, and examples/file/cloudquery.yaml — same structure as postgresql adapted for file plugin (`ghcr.io/infobloxopen/cloudquery-plugin-file:v5.5.1`)

**Checkpoint**: At this point, User Stories 1 AND 2 should both work — images are published and deployable to Kubernetes with example manifests

---

## Phase 5: User Story 3 — Maintainer Adds New Plugin via Manifest Edit (Priority: P3)

**Goal**: A maintainer adds a new plugin or version by editing a single YAML block in `plugins.yaml` — CI picks it up automatically without any workflow, Dockerfile, or script changes.

**Independent Test**: Add a new entry (e.g., a hypothetical csv destination plugin) to `plugins.yaml`, open a PR, and confirm CI validates the entry, builds the image, and runs the smoke test — all without touching any workflow file.

### Implementation for User Story 3

- [x] T020 [US3] Create PR validation workflow at .github/workflows/pr-validate.yaml per contracts/ci-workflows.md § Workflow 1 — trigger on `pull_request` targeting `main` (path filters: `plugins.yaml`, `Dockerfile`, `scripts/**`, `.github/**`); permissions: `contents: read`; steps: validate manifest schema, verify upstream tags/commits, generate matrix, build images (no push) via composite action, run smoke test per matrix entry
- [x] T021 [P] [US3] Create ADR for monorepo tag checkout strategy at docs/adr/001-monorepo-tag-checkout.md — document decision to build from upstream monorepo tags (D1 from research.md), alternatives considered, consequences
- [x] T022 [P] [US3] Create ADR for distroless base image choice at docs/adr/002-distroless-base-image.md — document decision to use `gcr.io/distroless/static-debian12:nonroot` (D2 from research.md), alternatives (Alpine, scratch), consequences
- [x] T023 [P] [US3] Create ADR for Go entrypoint wrapper design at docs/adr/003-go-entrypoint-wrapper.md — document decision to use Go wrapper over shell script (D3 from research.md), env var bridge pattern, consequences

**Checkpoint**: At this point, the full PR → merge → publish cycle is complete. Maintainers can add plugins by editing only `plugins.yaml`

---

## Phase 6: User Story 4 — Consumer Discovers Available Images via Build Index (Priority: P4)

**Goal**: Consumers (humans or automation) consult a machine-readable `build-index.json` and a human-readable `docs/build-index.md` to discover which plugin images are available, their digests, and upstream provenance.

**Independent Test**: After a successful `main` build, download the `build-index.json` workflow artifact and verify its schema; check that `docs/build-index.md` has been updated.

### Implementation for User Story 4

- [x] T024 [US4] Create build index generation script at scripts/generate-build-index.sh — aggregate per-plugin metadata (kind, name, version, image ref, digest per arch, upstream repo/tag/commit, build timestamp, SBOM/provenance/cosign status) into build-index.json conforming to schemas/build-index.schema.json; also generate Markdown table and write to docs/build-index.md
- [x] T025 [US4] Add build index generation step to publish workflow in .github/workflows/publish.yaml — after all matrix jobs complete: run generate-build-index.sh, upload build-index.json as workflow artifact, commit updated docs/build-index.md to main
- [x] T026 [P] [US4] Create initial build index documentation page at docs/build-index.md with header explaining the page is auto-generated, table structure placeholder, and link to the JSON artifact

**Checkpoint**: At this point, every successful publish run produces a machine-readable index and updates the human-readable docs

---

## Phase 7: User Story 5 — PR Author Gets Fast Feedback on Manifest and Image Quality (Priority: P5)

**Goal**: PR authors receive automated, ordered, actionable feedback on manifest changes — schema validation → upstream ref verification → image build → smoke test — with clear error messages identifying exact issues.

**Independent Test**: Open a PR with a deliberately invalid manifest entry (bad schema, nonexistent upstream tag) and confirm CI fails with actionable error messages within 5 minutes before any image build starts.

### Implementation for User Story 5

- [x] T027 [US5] Enhance PR validation with structured step ordering and job summary in .github/workflows/pr-validate.yaml — add GitHub Actions job summary output with per-plugin status table, ensure validation steps short-circuit on first failure with clear error messages (schema errors include field name/line, ref errors include the exact tag that failed)
- [x] T028 [US5] Add actionable error messages and line-level feedback to scripts/validate-manifest.sh — on schema validation failure output the exact field path and constraint violated, on upstream ref failure output the plugin name/tag and suggest checking the upstream repo; exit with distinct error codes per failure type

**Checkpoint**: All five user stories are now independently functional and testable

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories — DX, documentation, and optional enhancements

- [x] T029 [P] Create Makefile with local DX targets at Makefile — targets: `build-<name>` (single plugin), `build-all`, `smoke-test-<name>`, `validate`, `clean`, `help`; shell out to scripts/ for implementation
- [x] T030 [P] Create project README at README.md — sections: Purpose, Architecture overview, Quickstart (reference quickstart.md patterns), Manifest reference, Image naming convention, K8s deployment guide, Contributing, License
- [x] T031 [P] Create optional upstream update check workflow at .github/workflows/check-updates.yaml per contracts/ci-workflows.md § Workflow 3 — schedule (weekly cron) or `workflow_dispatch`; for each plugin check latest upstream tag, if newer create branch and open PR with changelog
- [x] T032 Run quickstart.md end-to-end validation — follow the steps in specs/001-oci-image-pipeline/quickstart.md to verify local build, smoke test, and manifest validation all work correctly

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1: Setup ──────────────────────────► Phase 2: Foundational
                                                │
                                                │ BLOCKS all user stories
                                                ▼
                        ┌───────────────────────┼───────────────────────┐
                        │                       │                       │
                        ▼                       ▼                       ▼
                   Phase 3: US1            Phase 4: US2            Phase 5: US3
                   (P1 — GHCR)             (P2 — K8s)             (P3 — PR validation)
                        │                                               │
                        ▼                                               │
                   Phase 6: US4                                         │
                   (P4 — Build index,                                   │
                    extends publish.yaml)                                ▼
                                                                   Phase 7: US5
                                                                   (P5 — PR feedback,
                                                                    refines pr-validate.yaml)
                        │                       │                       │
                        └───────────────────────┼───────────────────────┘
                                                ▼
                                        Phase 8: Polish
```

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) — no dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) — no dependencies on other stories (examples reference images by tag, don't need live images)
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) — no dependencies on other stories
- **User Story 4 (P4)**: Depends on **US1** completion (extends publish.yaml with build index step)
- **User Story 5 (P5)**: Depends on **US3** completion (refines pr-validate.yaml and validate-manifest.sh)

### Within Each User Story

- Core workflow/script before supplementary files
- Shared infrastructure (composite action) is in Foundational phase
- Story complete before moving to next priority (when working sequentially)

### Parallel Opportunities

**Phase 1**: T002, T003, T004 can all run in parallel (different files, no deps)

**Phase 2**: Two parallel groups:
- Group A (schemas): T006 + T007 — parallel, no dependencies beyond T001
- Group B (scripts): T010 + T011 + T012 — parallel (different scripts, no deps beyond T005)
- T008 and T009 must be sequential (Dockerfile references entrypoint, but they're independent files)
- T013 depends on T005 + T008; T014 depends on T008 + T009 + T010 + T012

**Phase 3 (US1)**: T015 depends on T014; T016 is parallel (different file)

**Phase 4 (US2)**: T017 + T018 + T019 — all three parallel (different plugin directories, identical patterns)

**Phase 5 (US3)**: T020 depends on T014; T021 + T022 + T023 — all three parallel (independent ADR files)

**Phase 6 (US4)**: T024 before T025 (script before workflow integration); T026 parallel with T024

**Phase 7 (US5)**: T027 and T028 can be worked in parallel (workflow vs script, but both touch validation logic)

**Phase 8**: T029 + T030 + T031 — all parallel (different files); T032 is last (end-to-end validation)

---

## Parallel Example: User Story 2

```bash
# All three plugin K8s example sets can be created in parallel:
Task T017: "Create postgresql K8s examples in examples/postgresql/"
Task T018: "Create s3 K8s examples in examples/s3/"
Task T019: "Create file K8s examples in examples/file/"
```

## Parallel Example: Foundational Phase

```bash
# Schemas can be created in parallel:
Task T006: "Create manifest schema in schemas/plugins-manifest.schema.json"
Task T007: "Create build index schema in schemas/build-index.schema.json"

# Scripts can be created in parallel:
Task T010: "Create validate-manifest.sh in scripts/"
Task T011: "Create generate-matrix.sh in scripts/"
Task T012: "Create smoke-test.sh in scripts/"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete **Phase 1**: Setup (T001–T004)
2. Complete **Phase 2**: Foundational (T005–T014) — CRITICAL, blocks all stories
3. Complete **Phase 3**: User Story 1 (T015–T016)
4. **STOP and VALIDATE**: Push manifest change to `main`, verify images appear in GHCR
5. Deploy/demo if ready — this is the minimum viable pipeline

### Incremental Delivery

1. Setup + Foundational → Foundation ready (16 tasks)
2. Add US1 → Test publish flow → **MVP!** (2 tasks, 18 total)
3. Add US2 → K8s examples available → Deploy/Demo (3 tasks, 21 total)
4. Add US3 → PR validation active → Full dev workflow (4 tasks, 25 total)
5. Add US4 → Build index tracking → Compliance met (3 tasks, 28 total)
6. Add US5 → PR feedback polished → DX complete (2 tasks, 30 total)
7. Polish → Makefile, README, update check → Production ready (4 tasks, 34 total)

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (publish workflow)
   - Developer B: User Story 2 (K8s examples) — can start immediately
   - Developer C: User Story 3 (PR validation + ADRs) — can start immediately
3. After US1 completes: Developer A picks up US4 (build index)
4. After US3 completes: Developer C picks up US5 (PR feedback polish)
5. Team collaborates on Polish phase

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks in same phase
- [US#] label maps task to specific user story for traceability
- Each user story is independently completable and testable at its checkpoint
- Commit after each task or logical group
- Stop at any checkpoint to validate the story independently
- All scripts must use `#!/usr/bin/env bash` + `set -euo pipefail` per constitution
- All GHA actions must be pinned to full commit SHAs per constitution Article III
- Dockerfile must produce distroless final image with non-root user per constitution Article IV
- OCI labels must match the set defined in data-model.md § OCI Image
