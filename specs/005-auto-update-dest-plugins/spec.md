# Feature Specification: Build All Destination Plugins with Automated Daily Updates

**Feature Branch**: `005-auto-update-dest-plugins`  
**Created**: 2026-02-22  
**Status**: Draft  
**Input**: User description: "build all open source cloudquery destination plugins and ensure the latest release for each tag is updated in the plugins.yaml and checked in automatically to main at least once a day"

## User Scenarios & Testing *(mandatory)*

### User Story 1 — All Go-based destination plugins are built and published (Priority: P1)

As a **platform engineer**, I want every open-source Go-based CloudQuery destination plugin from the Infoblox fork to be defined in `plugins.yaml` and built as an OCI image, so that I can deploy any supported destination without waiting for manual additions.

**Why this priority**: This is the core deliverable. Without all plugins in the manifest, the automated update (US2) has nothing to update. Expanding from 3 plugins to 20+ unlocks immediate value for any team needing BigQuery, Kafka, MongoDB, MySQL, ClickHouse, etc.

**Independent Test**: Add all destination plugin entries to `plugins.yaml`, run `make validate` to confirm all tags and commits resolve, and run `make build PLUGIN=<name>` for each plugin to confirm successful image builds.

**Acceptance Scenarios**:

1. **Given** `plugins.yaml` currently defines only s3, file, and postgresql, **When** the migration is complete, **Then** `plugins.yaml` contains entries for all Go-based destination plugins available in the fork (at least 20 plugins) with valid tags and commit SHAs.
2. **Given** a new plugin entry is added (e.g., kafka), **When** `make validate` runs, **Then** the tag and commit resolve successfully against `https://github.com/infobloxopen/cloudquery`.
3. **Given** a plugin that requires CGO (e.g., sqlite, duckdb, snowflake), **When** its manifest entry declares `build.cgo_required: true`, **Then** the build pipeline uses `CGO_ENABLED=1` and a distroless base image with libc support (e.g., `gcr.io/distroless/base-debian12:nonroot`), producing a working OCI image.
4. **Given** the `sqlite-python` plugin directory exists in the fork, **When** the manifest is generated, **Then** it is excluded because it is a Python plugin and cannot be built with the Go-based pipeline.
5. **Given** all plugin entries are in the manifest, **When** CI runs on the `main` branch, **Then** all buildable plugins produce multi-arch OCI images published to `ghcr.io/infobloxopen/cq-destination-<name>:<version>-<git-suffix>`, where `<git-suffix>` is derived from this repository's latest tag (e.g., `g<short-sha>` or the repo's own semver tag).

---

### User Story 2 — Automated daily update detects and applies new plugin releases (Priority: P1)

As a **CI/CD operator**, I want a scheduled process that runs at least once daily, checks the Infoblox fork for new plugin release tags, updates `plugins.yaml` with the latest versions, and commits the changes to `main`, so that our images always track the latest upstream releases without manual intervention.

**Why this priority**: Equally critical to US1. Manual tracking of 20+ plugins is unsustainable. Automation eliminates drift between the fork's releases and the images we build.

**Independent Test**: Simulate a new tag being available in the fork. Run the update script. Verify that `plugins.yaml` is updated with the new version, tag, and commit SHA, and that the change is committed.

**Acceptance Scenarios**:

1. **Given** the fork has a newer release tag for a plugin (e.g., `plugins-destination-postgresql-v8.15.0`) than what is in `plugins.yaml` (v8.14.1), **When** the daily update runs, **Then** `plugins.yaml` is updated with the new version (`v8.15.0`), new tag (`plugins-destination-postgresql-v8.15.0`), and the corresponding commit SHA.
2. **Given** no plugins have newer releases, **When** the daily update runs, **Then** no changes are made and no commit is created.
3. **Given** the daily update detects new versions for 3 plugins, **When** it updates `plugins.yaml`, **Then** all 3 are updated in a single commit with a descriptive message listing what changed.
4. **Given** the daily update runs and `make validate` fails after updating, **Then** the update is rolled back and an alert is raised (via CI failure notification) so a human can investigate.
5. **Given** the scheduled process is configured, **When** 24 hours pass, **Then** the check has run at least once.

---

### User Story 3 — Update script can be run manually for on-demand checks (Priority: P2)

As a **developer**, I want to run the update script manually (locally or in CI) to check for new plugin versions on demand, so that I can trigger updates outside the daily schedule when I know a new release is available.

**Why this priority**: Provides flexibility beyond the daily schedule. Low incremental cost since the update script exists from US2.

**Independent Test**: Run the update script manually from a developer workstation. Verify it reports which plugins have updates available and optionally applies them.

**Acceptance Scenarios**:

1. **Given** a developer runs the update script with a dry-run flag, **When** the fork has newer versions available, **Then** the script outputs a table showing plugin name, current version, and available version without modifying any files.
2. **Given** a developer runs the update script without dry-run, **When** updates are available, **Then** `plugins.yaml` is updated locally (no auto-commit) and `make validate` can be run to verify.

---

### User Story 4 — New destination plugins in the fork are detected automatically (Priority: P3)

As a **platform engineer**, I want the automated process to detect when new destination plugins appear in the fork (i.e., new `plugins-destination-*` tags that don't match any existing entry in `plugins.yaml`), so that I am notified and can add them to the manifest.

**Why this priority**: Future-proofing. Once all current plugins are in the manifest, new upstream plugins will occasionally appear. Auto-detection prevents them from being missed indefinitely.

**Independent Test**: Add a mock tag for a non-existent plugin to the test scenario. Verify the script detects it and surfaces a notification.

**Acceptance Scenarios**:

1. **Given** the fork contains tags for a destination plugin not yet in `plugins.yaml` (e.g., a hypothetical `plugins-destination-redshift-v1.0.0`), **When** the daily update runs, **Then** the process logs a notice identifying the new plugin and its latest stable tag, but does NOT auto-add it (requires manual review to determine build configuration).
2. **Given** a new plugin is detected, **When** the CI run completes, **Then** a summary comment or log section lists newly detected plugins for human review.

---

### User Story 5 — Weekly Go version update keeps builds on latest stable Go (Priority: P2)

As a **platform engineer**, I want a weekly automated workflow to update the `go_version` in every plugin entry of `plugins.yaml` to the latest stable Go release (with a 2-week stabilization buffer), so that all plugin builds benefit from Go security patches and performance improvements without manual tracking.

**Why this priority**: Go releases can include critical security fixes. Automating the update with a 2-week buffer strikes a balance between staying current and avoiding day-zero regressions.

**Independent Test**: Simulate a Go release that is 3 weeks old. Run the workflow. Verify all `go_version` fields in `plugins.yaml` are updated.

**Acceptance Scenarios**:

1. **Given** Go 1.23.1 was released 3 weeks ago and `plugins.yaml` entries specify `go_version: 1.23.0`, **When** the weekly workflow runs on `main`, **Then** all plugin entries are updated to `go_version: 1.23.1` and the change is committed.
2. **Given** the latest stable Go release was published less than 2 weeks ago, **When** the weekly workflow runs, **Then** no changes are made.
3. **Given** the workflow is triggered on a feature branch, **When** it evaluates, **Then** it exits without making any changes (main-only).

---

### Edge Cases

- **Plugin requires CGO (sqlite, duckdb, snowflake)**: These plugins may depend on C libraries. The default build uses `CGO_ENABLED=0` with a fully static distroless base image. Plugins that require CGO MUST opt in via a `build.cgo_required: true` field in their plugin definition. When this field is set, the build pipeline uses `CGO_ENABLED=1` and a distroless base image that includes libc (e.g., `gcr.io/distroless/base-debian12:nonroot` instead of `static-debian12`). This is strictly an exception — the vast majority of plugins remain fully static.
- **Python plugin (sqlite-python)**: Cannot be built with the Go pipeline. Must be excluded from the manifest entirely.
- **Pre-release / RC tags**: The update script must only consider stable release tags (matching `^plugins-destination-<name>-v\d+\.\d+\.\d+$`). Tags with `-rc`, `-beta`, `-alpha`, or other suffixes are ignored.
- **Version downgrade protection**: If the fork somehow contains a tag with a lower version than what's in `plugins.yaml`, the update script must NOT downgrade. It only moves forward.
- **`test` plugin**: The `test` plugin is a development/testing utility. It should be included in the manifest for completeness but excluded from image publishing to GHCR (controlled via a `publish: false` field or equivalent).
- **Tag exists but commit SHA changes (force-push)**: The update script uses `git ls-remote` to resolve tags. If a tag is force-pushed to a different SHA, the script should detect the mismatch and update the commit SHA (with a warning in the commit message).
- **Network failure during daily update**: If `git ls-remote` fails due to network issues, the script should retry up to 3 times with backoff. If all retries fail, the job fails and no changes are made.
- **Major version bump changing directory structure**: If a new major version moves the plugin to a different directory (e.g., `plugins/destination/s3` → `plugins/destination/s3/v8`), the automated update cannot handle this. Detection should log a warning for manual intervention.
- **Multiple new versions released between daily checks**: The script picks only the latest stable version, skipping intermediate releases. This is correct behavior — we always want to be on the latest.
- **`ldflags_version_path` changes across major versions**: If a new major version changes the Go module path (e.g., `.../s3/v7/...` → `.../s3/v8/...`), the update script must update this field too. The path follows the pattern `github.com/cloudquery/cloudquery/plugins/destination/<name>/v<major>/resources/plugin.Version`.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The `plugins.yaml` manifest MUST contain entries for all Go-based destination plugins available in the Infoblox fork with stable release tags. As of this specification, these are: azblob, bigquery, clickhouse, csv, duckdb, elasticsearch, file, firehose, gcs, gremlin, kafka, meilisearch, mongodb, mssql, mysql, neo4j, postgresql, s3, snowflake, sqlite (20 Go plugins). The `test` plugin MUST also be defined but marked as non-publishable. The `motherduck` plugin does NOT exist as a separate plugin (MotherDuck is accessed via the duckdb plugin) and MUST NOT be included.
- **FR-002**: Each plugin entry MUST specify: name, kind (`destination`), version, upstream repo (`https://github.com/infobloxopen/cloudquery`), upstream tag, upstream commit SHA, plugin directory path, Go version, and `ldflags_version_path`.
- **FR-003**: The `sqlite-python` plugin MUST NOT be included in the manifest — it is a Python plugin incompatible with the Go build pipeline.
- **FR-004**: An automated update script MUST exist that queries the Infoblox fork for the latest stable release tag of each destination plugin in `plugins.yaml`, compares it with the current version, and updates the entry if a newer version is available.
- **FR-005**: The update script MUST update all three version-sensitive fields when a new version is detected: `version`, `upstream.tag`, and `upstream.commit`. It MUST also update `build.ldflags_version_path` if the major version number changes.
- **FR-006**: The update script MUST only consider stable release tags (matching the pattern `^plugins-destination-<name>-v\d+\.\d+\.\d+$`) and MUST ignore pre-release, RC, and other non-standard tags.
- **FR-007**: The update script MUST support a dry-run mode that reports available updates without modifying any files.
- **FR-008**: A scheduled CI job MUST run the update script at least once every 24 hours, apply changes to `plugins.yaml`, run `make validate` to verify, and open a pull request to `main` with auto-merge enabled. Direct pushes to `main` are prohibited per the constitution; the PR MUST pass all required status checks before merging.
- **FR-009**: If `make validate` fails after the update script modifies `plugins.yaml`, the CI job MUST NOT commit the changes and MUST fail visibly so operators are notified.
- **FR-010**: The update script MUST NOT downgrade any plugin version. If the current version in `plugins.yaml` is newer than the latest tag in the fork, no change is made for that plugin.
- **FR-011**: The daily update MUST report (via CI log output) newly detected destination plugins that have tags in the fork but are not yet defined in `plugins.yaml`, without auto-adding them.
- **FR-012**: Plugins that require CGO MUST declare `build.cgo_required: true` in their manifest entry. When this field is set, the build pipeline MUST use `CGO_ENABLED=1` and a distroless base image with libc support instead of the fully static base image. By default, all plugins are built fully static (`CGO_ENABLED=0`, `distroless/static`). A build failure for one plugin MUST NOT block the build of other plugins.
- **FR-013**: The update commit message MUST clearly list which plugins were updated and from which version to which version (e.g., "chore: update postgresql v8.14.1 → v8.15.0, kafka v5.7.1 → v5.8.0").
- **FR-014**: Every OCI image tag MUST include a git suffix derived from this repository's tag or commit. The format is `<upstream-version>-<git-suffix>` (e.g., `ghcr.io/infobloxopen/cq-destination-postgresql:v8.14.1-g1a2b3c4`). The `cq-` prefix identifies the image as originating from the upstream CloudQuery repo; the git suffix identifies which build of this repo produced it.
- **FR-015**: A scheduled CI workflow MUST run once per week on the `main` branch to update the `go_version` field in every plugin entry in `plugins.yaml` to the latest stable Go release that has been available for at least 2 weeks. This ensures new Go releases are adopted after a stabilization period.
- **FR-016**: The Go version update workflow MUST NOT run on feature branches. If no newer stable Go version meeting the 2-week criterion exists, no changes are made.

### Key Entities

- **Plugin Manifest Entry** (`plugins.yaml`): Defines a single destination plugin with its upstream coordinates (repo, tag, commit) and build configuration (plugin_dir, go_version, ldflags_version_path). Each entry maps 1:1 to a published OCI image.
- **Update Script**: A script that compares `plugins.yaml` entries against the fork's git tags, detects version drift, and updates the manifest. Supports dry-run and apply modes.
- **Scheduled CI Job**: A CI workflow with scheduled trigger (cron) that runs the update script, validates, and commits. Also supports manual triggering.
- **Plugin Tag**: A git tag in the fork following the pattern `plugins-destination-<name>-v<semver>`. Tags are the source of truth for available versions.
- **Image Git Suffix**: A short identifier derived from this repository's tag or commit (e.g., `g1a2b3c4`). Appended to every OCI image tag to provide traceability back to the exact build of this repo that produced the image.
- **Go Version Update Workflow**: A weekly CI workflow (main-only) that checks for the latest stable Go release at least 2 weeks old and updates all `go_version` fields in `plugins.yaml`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `plugins.yaml` contains at least 20 destination plugin entries, all passing `make validate`.
- **SC-002**: New plugin releases in the fork are reflected in `plugins.yaml` within 24 hours without manual intervention.
- **SC-003**: The update script completes a full check of all plugins in under 2 minutes.
- **SC-004**: Zero manual commits are needed to update plugin versions after initial setup (excluding new plugin additions and build failures).
- **SC-005**: The dry-run mode accurately reports all available updates matching what the apply mode would change.
- **SC-006**: All plugins that can build with `CGO_ENABLED=0` produce working OCI images that pass smoke tests (gRPC port responds within 30 seconds).

## Assumptions

- The Infoblox fork at `https://github.com/infobloxopen/cloudquery` will continue to be synced with upstream CloudQuery, receiving new plugin release tags.
- All Go-based destination plugins follow the same monorepo structure: `plugins/destination/<name>/` with a standard Go module layout.
- The `ldflags_version_path` follows the convention `github.com/cloudquery/cloudquery/plugins/destination/<name>/v<major>/resources/plugin.Version` for all plugins. If a plugin deviates, it will be caught during `make validate` or build.
- Plugins requiring CGO (e.g., sqlite, duckdb, snowflake) declare `build.cgo_required: true` in the manifest and are built with `CGO_ENABLED=1` using a distroless base image with libc. This is an exception-basis mechanism; most plugins are fully static.
- The `test` plugin is included in the manifest for completeness and validation but is not published to GHCR.
- The scheduled CI trigger provides sufficient reliability for a daily check (known limitation: cron triggers may be delayed during high platform load).
- The update script has write access to `main` branch via a bot token or CI app with appropriate permissions.

## Scope Boundaries

### In Scope

- Adding all Go-based destination plugin entries to `plugins.yaml`
- Creating an update script to detect and apply new plugin versions
- Creating a scheduled CI workflow for daily automation
- Dry-run mode for the update script
- Detection (but not auto-addition) of new plugins

### Out of Scope

- Building Python plugins (`sqlite-python`)
- Source plugins (only destination plugins are covered)
- Building a custom CloudQuery CLI image
- Modifying the JSON schema or build scripts (they already work dynamically)
- Publishing the `test` plugin to GHCR
