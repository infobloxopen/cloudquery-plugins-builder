# Feature Specification: Use Infoblox Fork of CloudQuery for Image Builds

**Feature Branch**: `004-use-fork-repo`  
**Created**: 2026-02-22  
**Status**: Draft  
**Input**: User description: "We now maintain our own fork of cloudquery, we must use our FORK of cloudquery not the upstream one for building images. https://github.com/infobloxopen/cloudquery. Update all the references to this but still make sure there is a way to check out in the original path if that is important."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Build plugins from fork repository (Priority: P1)

As a pipeline operator, I want all plugin image builds to clone source code from the Infoblox fork (`https://github.com/infobloxopen/cloudquery`) instead of the upstream repository (`https://github.com/cloudquery/cloudquery`), so that builds use source code under Infoblox's control and any internal patches are included.

**Why this priority**: This is the core change — without it, builds still pull from upstream, defeating the purpose of maintaining a fork.

**Independent Test**: Can be fully tested by running `make build PLUGIN=postgresql` and verifying the Docker build log shows the clone URL as `https://github.com/infobloxopen/cloudquery`.

**Acceptance Scenarios**:

1. **Given** a developer runs `make build PLUGIN=postgresql`, **When** the Docker build executes the `git clone` step, **Then** the clone URL is `https://github.com/infobloxopen/cloudquery` (not `https://github.com/cloudquery/cloudquery`).
2. **Given** the `plugins.yaml` manifest is inspected, **When** a reviewer reads the `upstream.repo` field for any plugin, **Then** every plugin entry shows `https://github.com/infobloxopen/cloudquery` as the repo URL.
3. **Given** the Dockerfile default `UPSTREAM_REPO` build argument, **When** no override is provided, **Then** the default value is `https://github.com/infobloxopen/cloudquery`.

---

### User Story 2 - Manifest validation works against the fork (Priority: P1)

As a CI operator, I want `make validate` to verify upstream tags and commit SHAs against the fork repository, so that manifest validation succeeds when the fork contains the same tags and commits.

**Why this priority**: Without this, CI validation breaks immediately after switching the repo URL, blocking all merges.

**Independent Test**: Can be fully tested by running `make validate` and confirming all tag/commit checks pass against the fork.

**Acceptance Scenarios**:

1. **Given** `plugins.yaml` has `upstream.repo` set to the fork URL for all plugins, **When** `validate-manifest.sh` runs `git ls-remote` to verify tags, **Then** the tags resolve successfully against the fork.
2. **Given** the fork contains the same tags and commit SHAs as upstream, **When** commit SHA verification runs, **Then** all plugins pass validation.

---

### User Story 3 - Go module paths remain unchanged (Priority: P1)

As a build engineer, I want the Go module import paths (used in `ldflags_version_path`) to remain as `github.com/cloudquery/cloudquery/...`, so that the Go build compiles correctly since the fork's source code still declares `github.com/cloudquery/cloudquery` as its module path.

**Why this priority**: Changing these paths would break the Go build — they are Go module identifiers embedded in source code, not git clone URLs.

**Independent Test**: Can be fully tested by verifying the built plugin binary reports the correct version string via `--version` or gRPC metadata.

**Acceptance Scenarios**:

1. **Given** the `ldflags_version_path` values in `plugins.yaml` still reference `github.com/cloudquery/cloudquery/...`, **When** the Go build runs with `-X` ldflags, **Then** the version is injected correctly and the binary reports the expected version.
2. **Given** a reviewer inspects the `ldflags_version_path` fields, **When** they compare before and after this change, **Then** those fields are identical (unchanged).

---

### User Story 4 - Documentation reflects the fork (Priority: P2)

As a contributor reading the README or ADRs, I want all documentation references to point to the Infoblox fork where appropriate, so that instructions for adding new plugins or resolving tags are accurate.

**Why this priority**: Incorrect documentation leads to confusion and wasted time, but does not block builds.

**Independent Test**: Can be tested by following the "Adding a new plugin" instructions in the README and confirming they work against the fork URL.

**Acceptance Scenarios**:

1. **Given** a contributor follows the README's "Adding a new plugin" instructions, **When** they run `git ls-remote` as documented, **Then** the URL in the instructions is the fork URL and the command succeeds.
2. **Given** the README's manifest example block, **When** a reviewer reads it, **Then** the `upstream.repo` shows `https://github.com/infobloxopen/cloudquery`.
3. **Given** the ADR on monorepo tag checkout, **When** a reader reviews it, **Then** it references the fork as the source repository while noting the original upstream for historical context.

---

### User Story 5 - Spec documents reference the fork (Priority: P3)

As a specification author, I want existing specs within the `specs/` directory to reference the fork URL where they describe the upstream repository or manifest entries, so that specs remain accurate and consistent.

**Why this priority**: Specs are reference documents; inaccurate URLs cause confusion but do not affect runtime behavior.

**Independent Test**: Can be tested by searching specs for the old URL and confirming no actionable references remain.

**Acceptance Scenarios**:

1. **Given** the specs directory, **When** a search for `https://github.com/cloudquery/cloudquery` is performed in manifest/repo-reference contexts, **Then** all actionable references now point to the fork.

---

### Edge Cases

- What happens when the fork is missing a tag that upstream has? Manifest validation (`validate-manifest.sh`) will fail with a clear error message identifying the missing tag, prompting the team to sync the fork.
- What happens when a new plugin is added and the contributor uses the old upstream URL? The reviewer should catch this during PR review. The README instructions will direct contributors to use the fork URL. The JSON Schema does not restrict the repo to a specific URL (it accepts any HTTPS URL), so this is a process/documentation concern, not a schema enforcement issue.
- What happens if the fork's commit SHA differs from upstream for the same tag? If the fork rebases or force-pushes tags, the SHA will differ. The `commit` field in `plugins.yaml` must be updated to match the fork's SHA. `validate-manifest.sh` will catch any mismatch.
- What about `ldflags_version_path` values that contain `github.com/cloudquery/cloudquery`? These are Go module import paths, not git URLs. They must NOT be changed — the fork's Go source still declares `module github.com/cloudquery/cloudquery/...` in its `go.mod` files. Changing them would break the build.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The `plugins.yaml` manifest MUST set `upstream.repo` to `https://github.com/infobloxopen/cloudquery` for all plugin entries.
- **FR-002**: The Dockerfile's default `UPSTREAM_REPO` build argument MUST be changed from `https://github.com/cloudquery/cloudquery` to `https://github.com/infobloxopen/cloudquery`.
- **FR-003**: The `ldflags_version_path` values in `plugins.yaml` MUST remain unchanged (they are Go module paths, not git URLs).
- **FR-004**: The `upstream.tag` and `upstream.commit` values in `plugins.yaml` MUST remain valid — if the fork has the same tags and commits as upstream, they stay unchanged; if they differ, they MUST be updated to match the fork.
- **FR-005**: The `validate-manifest.sh` script MUST continue to work correctly, resolving tags and commits against whatever URL is in the `upstream.repo` field (no hardcoded upstream URL assumptions).
- **FR-006**: The `build.sh` script MUST continue to pass the `UPSTREAM_REPO` from the manifest to the Docker build, with no hardcoded URL assumptions.
- **FR-007**: The README MUST update all instructional references (manifest examples, `git ls-remote` commands, monorepo links) to use the fork URL.
- **FR-008**: The README MUST mention the original upstream repository (`https://github.com/cloudquery/cloudquery`) for attribution and historical context.
- **FR-009**: The ADR 001 (monorepo tag checkout) MUST be updated to reflect that builds now use the fork, while preserving the original decision rationale and noting the upstream origin.
- **FR-010**: Existing feature specs (001, 002, 003) that reference the upstream repo URL in manifest examples or instructions MUST be updated to use the fork URL.

### Key Entities

- **Plugin Manifest Entry** (`plugins.yaml`): Each entry's `upstream.repo` field is the git clone URL used during image builds. This is the primary field being changed from upstream to fork.
- **Dockerfile Build Argument**: `UPSTREAM_REPO` is an ARG with a default value — used in the `git clone` command. The default changes to the fork URL.
- **Go Module Path** (`ldflags_version_path`): A Go import path used with `-X` ldflags to inject the version at compile time. This is NOT a git URL and must NOT be modified.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of `upstream.repo` values in `plugins.yaml` point to `https://github.com/infobloxopen/cloudquery`.
- **SC-002**: Running `make build PLUGIN=<name>` for any plugin successfully clones from the fork and produces a working image.
- **SC-003**: Running `make validate` passes all schema and upstream reference checks against the fork.
- **SC-004**: All `ldflags_version_path` values remain unchanged from their pre-migration values.
- **SC-005**: A `grep` for `github.com/cloudquery/cloudquery` across all operational files (Dockerfile, plugins.yaml, scripts/) returns zero matches in git-URL contexts (Go module paths excluded).
- **SC-006**: The README's "Adding a new plugin" instructions work correctly when followed literally against the fork.

## Assumptions

- The Infoblox fork (`https://github.com/infobloxopen/cloudquery`) contains the same tags and commit SHAs as the upstream repository for currently pinned plugin versions. If tags were created differently or rebased, the `upstream.commit` values will need updating.
- The fork does not rename or restructure plugin directories — `plugin_dir` paths remain valid.
- The fork's Go source code retains `github.com/cloudquery/cloudquery` as the Go module path (standard for forks that don't intend to change import paths).
- The JSON Schema for `plugins-manifest.schema.json` does not need changes — it already accepts any HTTPS URL for the `upstream.repo` field.
- The `build.sh` and `validate-manifest.sh` scripts have no hardcoded references to the upstream URL — they read the repo URL from the manifest dynamically (confirmed by code review).
