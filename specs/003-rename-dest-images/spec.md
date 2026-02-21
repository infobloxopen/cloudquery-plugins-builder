# Feature Specification: Rename Destination Plugin OCI Images

**Feature Branch**: `003-rename-dest-images`  
**Created**: 2026-02-21  
**Status**: Draft  
**Input**: User description: "Rename destination plugin OCI images from cloudquery-plugin-<name> to cq-destination-<name> to align with CloudQuery taxonomy and cq-{source|destination}-<name> convention"

## User Scenarios & Testing *(mandatory)*

### User Story 1 — CI Publishes Images Under the New Naming Convention (Priority: P1)

When a maintainer merges changes to the main branch and the publish workflow runs, every destination plugin image MUST be pushed to GHCR under the new `cq-destination-<name>` naming pattern instead of the legacy `cloudquery-plugin-<name>` pattern.

**Why this priority**: This is the core change. Until the image name template is updated in the build pipeline, no downstream consumer can pull images by the new name, and the rest of the rename effort is moot.

**Independent Test**: Trigger a publish workflow (or local `scripts/build.sh`) for a single destination plugin and verify the resulting image reference uses `cq-destination-<name>`.

**Acceptance Scenarios**:

1. **Given** `plugins.yaml` lists `s3` as a `destination` plugin at version `v7.10.2`, **When** the publish workflow runs, **Then** the image is pushed to `ghcr.io/<org>/cq-destination-s3:v7.10.2`.
2. **Given** `plugins.yaml` lists `postgresql` as a `destination` plugin at version `v8.14.1`, **When** the publish workflow runs, **Then** the image is pushed to `ghcr.io/<org>/cq-destination-postgresql:v8.14.1`.
3. **Given** `plugins.yaml` lists `file` as a `destination` plugin at version `v5.5.1`, **When** the publish workflow runs, **Then** the image is pushed to `ghcr.io/<org>/cq-destination-file:v5.5.1`.

---

### User Story 2 — Source Plugins Use the Source Naming Convention (Priority: P1)

When a source plugin is built, the image name MUST follow the `cq-source-<name>` pattern. This ensures the naming convention is kind-aware and consistent for both source and destination plugins.

**Why this priority**: Equal to Story 1—without kind-aware naming the convention is incomplete and future source plugins would regress.

**Independent Test**: Add or verify a source plugin entry in `plugins.yaml` (e.g., `xkcd` with `kind: source`) and confirm the build produces `cq-source-xkcd:<version>`.

**Acceptance Scenarios**:

1. **Given** `plugins.yaml` contains a source plugin `xkcd` at version `v1.0.0`, **When** the build runs, **Then** the image is tagged `ghcr.io/<org>/cq-source-xkcd:v1.0.0`.
2. **Given** a new source plugin is added with `kind: source`, **When** the build runs, **Then** the image follows the `cq-source-<name>` pattern automatically.

---

### User Story 3 — OCI Labels and Metadata Reflect the New Name (Priority: P2)

All OCI labels set during the build (`org.opencontainers.image.title`, `org.opencontainers.image.description`) and build-index metadata entries MUST reference the new image names.

**Why this priority**: Important for discoverability, auditing, and the build-index documentation, but the images themselves will already be correctly named after Story 1 & 2.

**Independent Test**: Build a single plugin locally and inspect the image labels (`docker inspect`) to confirm they use `cq-destination-<name>` or `cq-source-<name>`.

**Acceptance Scenarios**:

1. **Given** the `s3` destination plugin is built, **When** the image labels are inspected, **Then** `org.opencontainers.image.title` is `cq-destination-s3`.
2. **Given** the build-index is generated after a publish run, **When** the `image` field for the `s3` entry is read, **Then** it contains `ghcr.io/<org>/cq-destination-s3:v7.10.2`.

---

### User Story 4 — Example Manifests and Documentation Are Updated (Priority: P3)

All example Kubernetes manifests, CloudQuery config files, README references, and existing spec documents MUST reference the new image names so that users following the documentation get working configurations.

**Why this priority**: Consumer-facing documentation. Lower priority because images work regardless of whether docs are updated, but stale docs will confuse users.

**Independent Test**: Grep the repository for `cloudquery-plugin-` after the change and confirm zero matches (outside of historical spec documents or ADRs that describe the migration itself).

**Acceptance Scenarios**:

1. **Given** the rename is complete, **When** a user follows the `examples/s3/deployment.yaml` manifest, **Then** the image reference is `ghcr.io/<org>/cq-destination-s3:<version>`.
2. **Given** the rename is complete, **When** a user reads the README, **Then** all image name examples use the new convention.

---

### Edge Cases

- What happens if a plugin entry in `plugins.yaml` has an unrecognized `kind` value (neither `source` nor `destination`)? The build MUST fail with a clear error message instead of producing an image with a malformed name.
- What happens if the `kind` field is missing from a plugin entry? The build MUST fail with an error indicating the mandatory field is absent.
- What happens when the smoke-test script runs against a newly built image? The image reference passed to the smoke test MUST use the new naming convention so the test pulls the correct image.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The image name template MUST be `cq-{kind}-{name}` where `{kind}` is the value of the plugin's `kind` field (e.g., `source`, `destination`) and `{name}` is the plugin's short name from `plugins.yaml`.
- **FR-002**: The local build script (`scripts/build.sh`) MUST construct image names using the `cq-{kind}-{name}:{version}` pattern.
- **FR-003**: The CI build action (`.github/actions/build-plugin/action.yaml`) MUST construct image names using the `cq-{kind}-{name}:{version}` pattern.
- **FR-004**: The publish workflow (`.github/workflows/publish.yaml`) MUST tag and push images using the `cq-{kind}-{name}:{version}` pattern in all references (image tag, build metadata JSON export).
- **FR-005**: OCI label `org.opencontainers.image.title` MUST be set to `cq-{kind}-{name}` for every built image.
- **FR-006**: The build-index generation script (`scripts/generate-build-index.sh`) MUST record image references using the new naming convention.
- **FR-007**: All example Kubernetes manifests (`examples/*/deployment.yaml`) MUST reference images using the new naming convention.
- **FR-008**: All example CloudQuery config files (`examples/*/cloudquery.yaml`, `examples/*/sync-job.yaml`) MUST reference images using the new naming convention for gRPC path references.
- **FR-009**: The build MUST fail with a descriptive error if the `kind` field is missing or contains an unrecognized value.
- **FR-010**: No backward-compatibility aliases, redirects, or dual-publishing under the old `cloudquery-plugin-<name>` convention SHALL be implemented. The old names are abandoned.
- **FR-011**: The smoke-test script (`scripts/smoke-test.sh`) MUST accept and operate on the new image name format.
- **FR-012**: The README MUST be updated to document the new naming convention and remove all references to the old `cloudquery-plugin-<name>` pattern.

### Key Entities

- **Plugin Manifest Entry**: A record in `plugins.yaml` describing a plugin. Key attributes: `name` (short name), `kind` (source or destination), `version`, upstream coordinates, and build parameters. The `kind` field drives the image name prefix.
- **OCI Image Reference**: The fully-qualified image name pushed to the container registry. Pattern: `ghcr.io/<org>/cq-{kind}-{name}:{version}`.
- **Build Index Record**: A provenance record tying a manifest entry to its published image. Key attributes: plugin kind, name, version, image reference, digest, upstream commit, build timestamp.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of published destination plugin images are reachable at `ghcr.io/<org>/cq-destination-<name>:<version>` after the next publish run.
- **SC-002**: 100% of published source plugin images are reachable at `ghcr.io/<org>/cq-source-<name>:<version>` after the next publish run.
- **SC-003**: Zero occurrences of the string `cloudquery-plugin-` exist in the codebase outside of historical documentation (prior specs, ADRs describing the migration) after the change is merged.
- **SC-004**: The build fails immediately with a clear error message when a plugin entry is missing the `kind` field or has an unrecognized `kind` value.
- **SC-005**: Downstream consumers of the build-index and example manifests can pull images without modification after adopting the new names.
- **SC-006**: Existing smoke tests pass when run against the newly named images with no modifications beyond the name change itself.

## Assumptions

- The `plugins.yaml` manifest already contains a `kind` field for every plugin entry (confirmed: current entries have `kind: destination`).
- The GHCR organization name (`infobloxopen`) does not change as part of this work.
- There is no registry-level redirect or alias mechanism needed—consumers must update their references to the new names.
- Source plugins will follow the same build pipeline and Dockerfile, differing only in the image name prefix.
- The `kind` field in `plugins.yaml` is authoritative for determining the image name prefix; no external mapping is needed.
