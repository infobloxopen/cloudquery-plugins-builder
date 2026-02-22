# Tasks: Use Infoblox Fork of CloudQuery for Image Builds

**Input**: Design documents from `/specs/004-use-fork-repo/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/repo-convention.md

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks grouped by user story. US1+US2+US3 are all P1 and tightly coupled (changing the same files achieves all three). US4 (docs) and US5 (specs) are independent documentation updates.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: No project initialization needed — this feature modifies existing files only.

- [X] T001 Verify fork parity by running `git ls-remote --tags https://github.com/infobloxopen/cloudquery` for all pinned tags

**Checkpoint**: Fork confirmed to have all required tags with matching SHAs. Safe to proceed.

---

## Phase 2: Foundational (Core Operational Files)

**Purpose**: Change the git clone URLs in the three operational files that control image builds. This phase satisfies US1 (build from fork), US2 (validation works), and US3 (Go paths unchanged — by explicitly NOT changing ldflags_version_path).

**⚠️ CRITICAL**: These changes must land together — partial migration would leave builds in an inconsistent state.

- [X] T002 [P] [US1] Update `upstream.repo` for s3 plugin from `https://github.com/cloudquery/cloudquery` to `https://github.com/infobloxopen/cloudquery` in plugins.yaml
- [X] T003 [P] [US1] Update `upstream.repo` for file plugin from `https://github.com/cloudquery/cloudquery` to `https://github.com/infobloxopen/cloudquery` in plugins.yaml
- [X] T004 [P] [US1] Update `upstream.repo` for postgresql plugin from `https://github.com/cloudquery/cloudquery` to `https://github.com/infobloxopen/cloudquery` in plugins.yaml
- [X] T005 [P] [US1] Update default `UPSTREAM_REPO` build argument from `https://github.com/cloudquery/cloudquery` to `https://github.com/infobloxopen/cloudquery` in Dockerfile
- [X] T006 [US2] Run `make validate` to confirm all tag/commit checks pass against the fork
- [X] T007 [US3] Verify all `ldflags_version_path` values in plugins.yaml are unchanged (still reference `github.com/cloudquery/cloudquery/...`)

**Checkpoint**: `plugins.yaml` and `Dockerfile` point to fork. Validation passes. Go module paths untouched.

---

## Phase 3: User Story 4 — Documentation Reflects the Fork (Priority: P2)

**Goal**: Update README and ADR so contributors follow correct instructions using the fork URL.

**Independent Test**: Follow the README "Adding a new plugin" instructions literally and confirm they work against the fork.

- [X] T008 [P] [US4] Update manifest example block `upstream.repo` URL in README.md (around L95)
- [X] T009 [P] [US4] Update monorepo link in "Adding a new plugin" section to point to the fork in README.md (around L107), adding a note that this is forked from the original `https://github.com/cloudquery/cloudquery`
- [X] T010 [P] [US4] Update `git ls-remote` command URL in "Adding a new plugin" section in README.md (around L109)
- [X] T011 [P] [US4] Add addendum to docs/adr/001-monorepo-tag-checkout.md noting migration to the Infoblox fork while preserving the original decision rationale and upstream attribution

**Checkpoint**: README instructions and ADR reflect the fork. Original upstream credited for attribution.

---

## Phase 4: User Story 5 — Spec Documents Reference the Fork (Priority: P3)

**Goal**: Update existing spec files that reference the upstream repo URL in manifest/instruction contexts.

**Independent Test**: Search specs for `https://github.com/cloudquery/cloudquery` in repo-reference contexts and confirm all actionable references point to the fork.

- [X] T012 [P] [US5] Update repo URL examples in specs/001-oci-image-pipeline/data-model.md (L20, L76, L110 — GIT_URL/SPEC_REFERENCE contexts only; preserve Go module paths)
- [X] T013 [P] [US5] Update repo URL examples in specs/001-oci-image-pipeline/plan.md (L191, L248, L261, L274 — GIT_URL/SPEC_REFERENCE contexts only; preserve Go module paths)
- [X] T014 [P] [US5] Update repo URL references in specs/002-xkcd-source-plugin/spec.md (L21, L85 — SPEC_REFERENCE contexts only; preserve Go module path at L119 and historical context at L117)
- [X] T015 [P] [US5] Update repo URL example in specs/003-rename-dest-images/quickstart.md (L66)

**Checkpoint**: All actionable spec references updated. Go module paths and historical research data preserved.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and verification across all changes.

- [X] T016 Run `grep -rn 'https://github.com/cloudquery/cloudquery' Dockerfile plugins.yaml scripts/` and confirm zero matches in git-URL contexts
- [X] T017 Run `make validate` as final end-to-end validation
- [X] T018 Run quickstart.md validation — follow the verification steps in specs/004-use-fork-repo/quickstart.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — verify fork parity first
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS validation and build testing
- **User Story 4 (Phase 3)**: Depends on Phase 2 (needs correct URLs established first)
- **User Story 5 (Phase 4)**: Independent of Phase 3 — can run in parallel with docs
- **Polish (Phase 5)**: Depends on all previous phases

### User Story Dependencies

- **US1 (Build from fork)**: T002–T005 change the URLs; T006 validates
- **US2 (Validation works)**: Satisfied when T006 passes after T002–T005
- **US3 (Go paths unchanged)**: Satisfied by T007 — explicit verification that no ldflags paths were modified
- **US4 (Documentation)**: T008–T011 — independent of US5, depends on US1 being done
- **US5 (Spec updates)**: T012–T015 — all parallelizable, independent of US4

### Parallel Opportunities

Within Phase 2:
- T002, T003, T004, T005 can all run in parallel (different files or different sections)

Within Phase 3:
- T008, T009, T010, T011 can all run in parallel (different files or different sections)

Within Phase 4:
- T012, T013, T014, T015 can all run in parallel (different files)

Across phases:
- Phase 3 and Phase 4 can run in parallel after Phase 2 completes

---

## Parallel Example: Phase 2 (Foundational)

```bash
# All manifest URL updates in parallel:
Task: T002 "Update upstream.repo for s3 plugin in plugins.yaml"
Task: T003 "Update upstream.repo for file plugin in plugins.yaml"
Task: T004 "Update upstream.repo for postgresql plugin in plugins.yaml"
Task: T005 "Update default UPSTREAM_REPO in Dockerfile"

# Then sequential validation:
Task: T006 "Run make validate"
Task: T007 "Verify ldflags_version_path unchanged"
```

---

## Implementation Strategy

### MVP First (US1 + US2 + US3 = Phase 1 + Phase 2)

1. Complete Phase 1: Verify fork parity
2. Complete Phase 2: Update operational files + validate
3. **STOP and VALIDATE**: `make validate` passes, `ldflags_version_path` unchanged
4. Builds now use the fork — core goal achieved

### Incremental Delivery

1. Phase 1 + Phase 2 → Operational migration complete (MVP)
2. Phase 3 → Documentation accurate for contributors
3. Phase 4 → Spec references consistent
4. Phase 5 → Final verification sweep

### Single-Developer Strategy

All phases are sequential for a single developer:
1. T001 → T002–T005 → T006–T007 (core migration: ~15 min)
2. T008–T011 (docs: ~15 min)
3. T012–T015 (specs: ~15 min)
4. T016–T018 (final validation: ~10 min)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- US1, US2, US3 are all P1 and tightly coupled — they share the same Phase 2
- Go module paths (`ldflags_version_path`) must NEVER be changed — they are Go import paths, not git URLs
- CQ CLI image references (`ghcr.io/cloudquery/cloudquery:latest`) in examples/ are out of scope
- No script or schema changes needed — scripts read URLs dynamically from manifest
- Total: 18 tasks across 5 phases
