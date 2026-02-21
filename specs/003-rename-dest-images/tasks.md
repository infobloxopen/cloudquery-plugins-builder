# Tasks: Rename Destination Plugin OCI Images

**Input**: Design documents from `/specs/003-rename-dest-images/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/naming-convention.md

**Tests**: Not explicitly requested in the feature specification. No test tasks generated.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: No project initialization needed — existing repo, existing files. This phase is intentionally empty.

_(All files already exist. No new directories, dependencies, or scaffolding required.)_

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Add kind validation guard to `build.sh` — defense-in-depth for FR-009. Must complete before image name changes to ensure invalid kinds are caught.

- [X] T001 Add `case` guard after KIND extraction (~line 72) in scripts/build.sh to reject unrecognized `kind` values with a descriptive error message per research decision R-002

**Checkpoint**: `build.sh` now rejects invalid `kind` values. Safe to proceed with image name formula changes.

---

## Phase 3: User Story 1 & 2 — CI Publishes Images Under Kind-Aware Naming (Priority: P1) 🎯 MVP

**Goal**: Change the image name formula from `cloudquery-plugin-<name>` to `cq-<kind>-<name>` in the build pipeline. US1 (destination naming) and US2 (source naming) are satisfied by the same formula change since the template is `cq-${KIND}-${NAME}` — the `kind` field determines the prefix automatically.

**Independent Test**: Run `make build PLUGIN=s3` locally and verify the image is tagged `cq-destination-s3:<version>`. Optionally add a source plugin entry and verify it produces `cq-source-<name>`.

### Implementation

- [X] T002 [P] [US1] Update IMAGE_NAME formula on line 68 of scripts/build.sh from `cloudquery-plugin-${PLUGIN_NAME}` to `cq-${KIND}-${PLUGIN_NAME}`
- [X] T003 [P] [US1] Update IMAGE formula on line 69 of .github/actions/build-plugin/action.yaml from `cloudquery-plugin-${{ inputs.name }}` to `cq-${{ inputs.kind }}-${{ inputs.name }}`
- [X] T004 [P] [US1] Update image field on line 107 of .github/workflows/publish.yaml from `cloudquery-plugin-${{ matrix.name }}` to `cq-${{ matrix.kind }}-${{ matrix.name }}`
- [X] T005 [US1] Update smoke-test target (~line 46) in Makefile to extract KIND via yq and use `cq-$${KIND}-$(PLUGIN)` in image name
- [X] T006 [US1] Update PLUGIN_SMOKE_TARGET macro (~line 54) in Makefile to extract KIND via yq and use `cq-$${KIND}-$(1)` in image name
- [X] T007 [US1] Update clean target (~line 98) in Makefile to extract KIND via yq and use `cq-$$KIND-$$plugin` in image name

**Checkpoint**: All 4 functional files now produce `cq-<kind>-<name>` image names. Both destination and source plugins are correctly named. US1 and US2 are satisfied.

---

## Phase 4: User Story 3 — OCI Labels and Metadata Reflect the New Name (Priority: P2)

**Goal**: Update OCI image labels (`org.opencontainers.image.title`) to use the new naming convention. Build-index metadata is already correct (no hardcoded names in `generate-build-index.sh`).

**Independent Test**: Build a plugin locally with `make build PLUGIN=s3`, then run `docker inspect` to verify `org.opencontainers.image.title` is `cq-destination-s3`.

### Implementation

- [X] T008 [P] [US3] Update OCI title label on line 102 of scripts/build.sh from `cloudquery-plugin-${PLUGIN_NAME}` to `cq-${KIND}-${PLUGIN_NAME}`
- [X] T009 [P] [US3] Update OCI title label on line 113 of .github/actions/build-plugin/action.yaml from `cloudquery-plugin-${{ inputs.name }}` to `cq-${{ inputs.kind }}-${{ inputs.name }}`

**Checkpoint**: OCI labels use new naming convention. Build-index auto-reflects changes via metadata JSON. US3 satisfied.

---

## Phase 5: User Story 4 — Example Manifests and Documentation (Priority: P3)

**Goal**: Update all example K8s manifests, CloudQuery configs, and README to reference the new image names. Ensure zero occurrences of `cloudquery-plugin-` remain outside historical specs/ADRs.

**Independent Test**: `grep -r "cloudquery-plugin-" --include="*.sh" --include="*.yaml" --include="*.md" --exclude-dir=specs --exclude-dir=docs/adr .` returns zero results.

### Implementation — Examples: File plugin

- [X] T010 [P] [US4] Update all `cloudquery-plugin-file` references (K8s names, labels, image ref) in examples/file/deployment.yaml to `cq-destination-file`
- [X] T011 [P] [US4] Update gRPC path from `cloudquery-plugin-file:7777` to `cq-destination-file:7777` in examples/file/cloudquery.yaml
- [X] T012 [P] [US4] Update gRPC path from `cloudquery-plugin-file:7777` to `cq-destination-file:7777` in examples/file/sync-job.yaml

### Implementation — Examples: S3 plugin

- [X] T013 [P] [US4] Update all `cloudquery-plugin-s3` references (K8s names, labels, image ref) in examples/s3/deployment.yaml to `cq-destination-s3`
- [X] T014 [P] [US4] Update gRPC path from `cloudquery-plugin-s3:7777` to `cq-destination-s3:7777` in examples/s3/cloudquery.yaml
- [X] T015 [P] [US4] Update gRPC path from `cloudquery-plugin-s3:7777` to `cq-destination-s3:7777` in examples/s3/sync-job.yaml

### Implementation — Examples: PostgreSQL plugin

- [X] T016 [P] [US4] Update all `cloudquery-plugin-postgresql` references (K8s names, labels, image ref) in examples/postgresql/deployment.yaml to `cq-destination-postgresql`
- [X] T017 [P] [US4] Update gRPC path from `cloudquery-plugin-postgresql:7777` to `cq-destination-postgresql:7777` in examples/postgresql/cloudquery.yaml
- [X] T018 [P] [US4] Update gRPC path from `cloudquery-plugin-postgresql:7777` to `cq-destination-postgresql:7777` in examples/postgresql/sync-job.yaml

### Implementation — Documentation

- [X] T019 [P] [US4] Update naming convention pattern and all image reference examples in README.md to use `cq-<kind>-<name>` pattern
- [X] T020 [P] [US4] Update usage comment example on line 7 of scripts/smoke-test.sh from `cloudquery-plugin-postgresql` to `cq-destination-postgresql`

**Checkpoint**: All examples and documentation reference new image names. `grep` for `cloudquery-plugin-` in active files returns zero results. US4 satisfied.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: ADR for the naming migration decision (constitution requirement), final validation.

- [X] T021 Create ADR documenting the naming migration decision in docs/adr/004-rename-image-convention.md per research decision R-006
- [X] T022 Run quickstart.md validation — verify `grep -r "cloudquery-plugin-" --include="*.sh" --include="*.yaml" --include="*.md" --exclude-dir=specs --exclude-dir=docs/adr .` returns zero results
- [X] T023 Verify `make build PLUGIN=s3` produces image tagged `cq-destination-s3:<version>` per quickstart.md instructions

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Empty — no work needed
- **Foundational (Phase 2)**: No dependencies — T001 can start immediately
- **US1 & US2 (Phase 3)**: Depends on Phase 2 (T001) — kind validation must be in place first
- **US3 (Phase 4)**: Depends on Phase 3 — label changes follow the same pattern as image name changes
- **US4 (Phase 5)**: No dependency on Phases 3/4 — can run in parallel with them (different files)
- **Polish (Phase 6)**: Depends on all story phases being complete

### User Story Dependencies

- **US1 & US2 (P1)**: Core pipeline change. Must complete first for any images to be published under new names.
- **US3 (P2)**: OCI label updates. Technically co-located with US1/US2 changes but logically separable.
- **US4 (P3)**: Documentation/examples. Fully independent — touches different files than US1-US3.

### Parallel Opportunities

- **Phase 3**: T002, T003, T004 can run in parallel (different files)
- **Phase 3**: T005, T006, T007 are sequential (same file: Makefile)
- **Phase 4**: T008, T009 can run in parallel (different files)
- **Phase 5**: ALL tasks (T010–T020) can run in parallel (every task touches a different file)
- **Phase 4 + Phase 5**: Can run in parallel with each other (no shared files)

---

## Parallel Example: Phase 5 (All Documentation)

```bash
# All 11 tasks can launch simultaneously — each touches a unique file:
T010: examples/file/deployment.yaml
T011: examples/file/cloudquery.yaml
T012: examples/file/sync-job.yaml
T013: examples/s3/deployment.yaml
T014: examples/s3/cloudquery.yaml
T015: examples/s3/sync-job.yaml
T016: examples/postgresql/deployment.yaml
T017: examples/postgresql/cloudquery.yaml
T018: examples/postgresql/sync-job.yaml
T019: README.md
T020: scripts/smoke-test.sh
```

---

## Implementation Strategy

### MVP First (US1 & US2 Only)

1. Complete Phase 2: Add kind validation guard (T001)
2. Complete Phase 3: Update image name formula in all 4 functional files (T002–T007)
3. **STOP and VALIDATE**: `make build PLUGIN=s3` → verify image is `cq-destination-s3:<version>`
4. The build pipeline now publishes under the new naming convention. MVP delivered.

### Incremental Delivery

1. Phase 2 → Kind validation guard → Foundation ready
2. Phase 3 → Image name formula → **MVP: CI publishes correct names** (US1+US2)
3. Phase 4 → OCI labels → **Labels match image names** (US3)
4. Phase 5 → Docs & examples → **Consumer-facing references updated** (US4)
5. Phase 6 → ADR + final validation → **Complete**

### Parallel Team Strategy

With multiple developers:

1. All developers: Complete Phase 2 (single task, T001)
2. Once T001 is done:
   - Developer A: Phase 3 (pipeline changes — T002–T007)
   - Developer B: Phase 5 (all docs/examples — T010–T020, fully parallel)
3. After Phase 3 completes:
   - Developer A: Phase 4 (OCI labels — T008–T009)
4. Developer A or B: Phase 6 (ADR + validation)

---

## Notes

- T002–T004 and T008–T009 edit the same files (build.sh, action.yaml) but different lines. If done by the same developer sequentially, they can be combined per-file. Listed separately for traceability to user stories.
- No test tasks generated — tests were not explicitly requested in the feature specification. Smoke tests are part of the existing pipeline and will validate the change automatically.
- `generate-build-index.sh` and `generate-matrix.sh` require zero changes (confirmed in research R-004).
- `scripts/validate-manifest.sh` requires zero changes (JSON Schema already constrains `kind`).
