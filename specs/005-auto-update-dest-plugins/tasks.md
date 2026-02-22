# Tasks: Build All Destination Plugins with Automated Daily Updates

**Input**: Design documents from `/specs/005-auto-update-dest-plugins/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: No test tasks — not requested in the feature specification.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Extend the manifest schema and build infrastructure to support CGO opt-in, git suffix tagging, and the `publish` field — prerequisites for all user stories.

- [X] T001 Add `cgo_required` and `publish` fields to JSON Schema in schemas/plugins-manifest.schema.json
- [X] T002 [P] Add CGO_ENABLED and BASE_IMAGE build args to Dockerfile, conditionally switch Stage 1 `go build` and Stage 3 base image based on CGO_ENABLED arg in Dockerfile
- [X] T003 [P] Update scripts/build.sh to read `build.cgo_required` from manifest via yq, set CGO_ENABLED and BASE_IMAGE build args accordingly, and pass them to docker buildx build
- [X] T004 [P] Update scripts/build.sh to generate git suffix via `git describe --always --dirty` and append it to IMAGE_NAME tag (format: `<version>-<git-suffix>`)
- [X] T005 [P] Update Makefile smoke-test targets to include git suffix when constructing image names for testing

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Resolve all 21 plugin upstream tags and commit SHAs. MUST complete before US1 can populate the manifest.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T006 Resolve upstream tags and commit SHAs for all 18 new destination plugins via `git ls-remote https://github.com/infobloxopen/cloudquery` (azblob, bigquery, clickhouse, csv, duckdb, elasticsearch, firehose, gcs, gremlin, kafka, meilisearch, mongodb, mssql, mysql, neo4j, snowflake, sqlite, test)
- [X] T007 Verify `ldflags_version_path` pattern for each new plugin by checking Go module path in `plugins/destination/<name>/` at the resolved tag

**Checkpoint**: All 21 plugin upstream coordinates (tag + SHA + ldflags path) are known and verified.

---

## Phase 3: User Story 1 — All Go-based destination plugins are built and published (Priority: P1) 🎯 MVP

**Goal**: Expand `plugins.yaml` from 3 to 21 destination plugins with valid tags, commits, and build config. All plugins build successfully.

**Independent Test**: Run `make validate` to confirm all tags/commits resolve. Run `make build PLUGIN=<name>` for several plugins to confirm image builds.

### Implementation for User Story 1

- [X] T008 [US1] Add non-CGO destination plugin entries to plugins.yaml: azblob, bigquery, clickhouse, csv, elasticsearch, firehose, gcs, gremlin, kafka, meilisearch, mongodb, mssql, mysql, neo4j, snowflake (15 plugins) — each with name, kind, version, upstream (repo/tag/commit), build (plugin_dir/go_version/ldflags_version_path)
- [X] T009 [US1] Add CGO destination plugin entries to plugins.yaml: sqlite (cgo_required: true), duckdb (cgo_required: true) — 2 plugins with `build.cgo_required: true`
- [X] T010 [US1] Add test plugin entry to plugins.yaml with `publish: false` — mark as non-publishable
- [X] T011 [US1] Run `make validate` to verify all 21 plugin entries resolve against the fork
- [X] T012 [US1] Build and verify at least 3 representative non-CGO plugins with `make build PLUGIN=<name>` (e.g., kafka, bigquery, clickhouse)
- [X] T013 [US1] Build and verify CGO plugins: `make build PLUGIN=sqlite` and `make build PLUGIN=duckdb` — confirm they build with CGO_ENABLED=1 and cc-debian12 base
- [X] T014 [P] [US1] Create ADR for CGO exception-basis design in docs/adr/005-cgo-exception-basis.md

**Checkpoint**: `plugins.yaml` has 21 entries, `make validate` passes, representative builds succeed including CGO plugins.

---

## Phase 4: User Story 2 — Automated daily update detects and applies new plugin releases (Priority: P1)

**Goal**: Create an update script that queries the fork for new tags, updates `plugins.yaml`, and a CI workflow that runs it daily and opens PRs.

**Independent Test**: Manually set a plugin version to an older value in `plugins.yaml`, run the update script, verify it detects and applies the update.

### Implementation for User Story 2

- [X] T015 [US2] Create scripts/update-plugins.sh per contracts/update-script.md — core loop: for each plugin in manifest, git ls-remote for latest stable tag, compare semver, update if newer
- [X] T016 [US2] Implement version comparison logic in scripts/update-plugins.sh — filter stable tags with regex `^plugins-destination-<name>-v[0-9]+\.[0-9]+\.[0-9]+$`, sort with `sort -V`, pick latest, compare with current
- [X] T017 [US2] Implement field update logic in scripts/update-plugins.sh — update version, upstream.tag, upstream.commit via yq; detect major version bumps and update ldflags_version_path
- [X] T018 [US2] Implement new plugin detection in scripts/update-plugins.sh — after processing existing plugins, scan all `plugins-destination-*` tags, report names not in manifest
- [X] T019 [US2] Implement error handling in scripts/update-plugins.sh — retry git ls-remote up to 3 times with exponential backoff (1s, 2s, 4s), validate yq availability
- [X] T020 [US2] Implement --commit flag in scripts/update-plugins.sh — create git commit with formatted message per contracts/update-script.md commit message format
- [X] T021 [US2] Create .github/workflows/update-plugins.yaml — daily cron schedule (0 6 * * *), GitHub App token via actions/create-github-app-token, checkout, run update script, make validate, create PR via peter-evans/create-pull-request
- [X] T022 [US2] Validate update-plugins.sh locally — set postgresql to v8.13.0 in plugins.yaml, run script, verify it updates to latest, run make validate

**Checkpoint**: `update-plugins.sh` detects version drift and updates manifest. CI workflow opens PRs for changes.

---

## Phase 5: User Story 3 — Update script can be run manually for on-demand checks (Priority: P2)

**Goal**: Add --dry-run mode to the update script for local developer use.

**Independent Test**: Run `./scripts/update-plugins.sh --dry-run` and verify it prints a table of current vs available versions without modifying files.

### Implementation for User Story 3

- [X] T023 [US3] Implement --dry-run flag in scripts/update-plugins.sh — output table (plugin, current version, available version, status) without modifying files
- [X] T024 [US3] Add --help flag to scripts/update-plugins.sh — print usage information per contracts/update-script.md interface

**Checkpoint**: Developers can check for updates locally without modifying the manifest.

---

## Phase 6: User Story 5 — Weekly Go version update keeps builds on latest stable Go (Priority: P2)

**Goal**: Create a script and CI workflow that updates `go_version` fields weekly to the latest stable Go release ≥2 weeks old.

**Independent Test**: Run `./scripts/update-go-version.sh --dry-run` and verify it reports the current and eligible Go versions.

### Implementation for User Story 5

- [X] T025 [US5] Create scripts/update-go-version.sh per contracts/go-version-update.md — fetch stable releases from go.dev/dl/?mode=json, resolve release dates via GitHub API, select newest version ≥14 days old
- [X] T026 [US5] Implement version comparison and go_version update logic in scripts/update-go-version.sh — compare candidate with current go_version, update all plugins via yq if newer
- [X] T027 [US5] Implement --dry-run flag in scripts/update-go-version.sh — report current and eligible versions without modifying files
- [X] T028 [US5] Implement main-branch guard in scripts/update-go-version.sh — exit immediately with no changes if not on main branch
- [X] T029 [US5] Create .github/workflows/update-go-version.yaml — weekly cron (0 9 * * 1), main-only, GitHub App token, run script, make validate, create PR via peter-evans/create-pull-request

**Checkpoint**: Weekly Go version updates work end-to-end, main-only guard prevents feature branch changes.

---

## Phase 7: User Story 4 — New destination plugins in the fork are detected automatically (Priority: P3)

**Goal**: Extract new plugin detection from the update script into a standalone script, and ensure the daily workflow surfaces new plugin notices in the CI log/PR body.

**Independent Test**: Verify the daily workflow log includes a section listing any newly detected plugins not in the manifest.

### Implementation for User Story 4

- [X] T030 [US4] Create scripts/detect-new-plugins.sh — standalone script that queries fork for all `plugins-destination-*` tags and reports plugin names not present in plugins.yaml
- [X] T031 [US4] Integrate detect-new-plugins.sh output into .github/workflows/update-plugins.yaml — add step that runs detection and includes results in PR body or CI summary

**Checkpoint**: New plugins in the fork are surfaced in CI logs for human review.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, ADRs, and final validation across all stories.

- [X] T032 [P] Create ADR for auto-update architecture in docs/adr/006-auto-update-pipeline.md
- [X] T033 [P] Update README.md with expanded plugin list, update/Go-version automation sections, and CGO opt-in documentation
- [X] T034 Run shellcheck on all new scripts: scripts/update-plugins.sh, scripts/update-go-version.sh, scripts/detect-new-plugins.sh
- [X] T035 Run full end-to-end validation: `make validate && make build-all` for all 21 plugins
- [X] T036 Run quickstart.md walkthrough to verify developer experience

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: No dependencies on Phase 1 (tag resolution is independent), but Phase 1 should complete first for schema support
- **US1 (Phase 3)**: Depends on Phase 1 (schema + build infra) and Phase 2 (resolved tags/SHAs) — BLOCKS all other user stories indirectly since US2 updates what US1 populates
- **US2 (Phase 4)**: Depends on US1 (needs populated manifest to update)
- **US3 (Phase 5)**: Depends on US2 (dry-run is a mode of the update script)
- **US5 (Phase 6)**: Depends on Phase 1 only (independent of US2/US3)
- **US4 (Phase 7)**: Depends on US2 (detection integrated into daily workflow)
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

- **US1 (P1)**: Phase 1 + Phase 2 → can start
- **US2 (P1)**: US1 complete → can start
- **US3 (P2)**: US2 complete → can start (adds dry-run to existing script)
- **US5 (P2)**: Phase 1 complete → can start (independent of US2/US3)
- **US4 (P3)**: US2 complete → can start

### Within Each User Story

- Schema/infra changes before manifest population
- Manifest population before build verification
- Core script logic before CI workflow integration
- Core implementation before polish/docs

### Parallel Opportunities

- Phase 1: T002, T003, T004, T005 can all run in parallel (different files)
- Phase 3: T014 (ADR) can run in parallel with T008-T013
- Phase 6 (US5): Can run in parallel with Phase 4 (US2) and Phase 5 (US3) since it modifies different files
- Phase 8: T032 and T033 can run in parallel

---

## Parallel Examples

### Phase 1 (all different files):
```
Task T002: Dockerfile — add CGO_ENABLED/BASE_IMAGE build args
Task T003: scripts/build.sh — read cgo_required from manifest
Task T004: scripts/build.sh — add git suffix (same file as T003, so do T003 first, then T004)
Task T005: Makefile — update smoke-test image name
```

### Phase 3 + Phase 6 (independent user stories):
```
Developer A: US1 — populate plugins.yaml (T008-T013)
Developer B: US5 — Go version update script (T025-T029)
```

---

## Implementation Strategy

### MVP First (US1 Only)

1. Complete Phase 1: Schema + build infra (T001-T005)
2. Complete Phase 2: Resolve all tags/SHAs (T006-T007)
3. Complete Phase 3: Populate manifest + verify builds (T008-T014)
4. **STOP and VALIDATE**: `make validate && make build-all` — all 21 plugins build
5. This is immediately valuable: all plugins are buildable

### Incremental Delivery

1. Phase 1 + 2 + 3 → US1 complete → All plugins defined and buildable (MVP!)
2. Phase 4 → US2 complete → Daily auto-updates via CI
3. Phase 5 → US3 complete → Developers can check updates locally
4. Phase 6 → US5 complete → Weekly Go version updates
5. Phase 7 → US4 complete → New plugin detection
6. Phase 8 → Polish → Docs, ADRs, final validation

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story for traceability
- CGO support is exception-basis only — only sqlite and duckdb need it
- All new scripts must follow constitution: `set -euo pipefail`, shellcheck, <200 lines, `#!/usr/bin/env bash`
- CI workflows must pin all actions to full commit SHA, set permissions per job
- Auto-update PRs require GitHub App token (not GITHUB_TOKEN) to trigger CI on the PR
