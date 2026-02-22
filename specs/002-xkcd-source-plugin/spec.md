# Feature Specification: XKCD Source Plugin

**Feature Branch**: `002-xkcd-source-plugin`
**Created**: 2026-02-16
**Status**: Draft
**Input**: User description: "Build the XKCD source plugin for the cloudquery-plugins-builder, referencing the upstream cloudquery/xkcd source plugin that fetches comic data from the XKCD API"

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Operator adds XKCD source plugin to the manifest and gets a published image (Priority: P1)

As an **operator**, I add the XKCD source plugin entry to `plugins.yaml` so that the existing CI pipeline automatically builds a multi-architecture OCI image and publishes it to GHCR, giving me a pull-ready image that syncs XKCD comic data without CloudQuery Hub authentication.

**Why this priority**: This is the core deliverable — registering the XKCD source plugin in the existing manifest-driven pipeline. Without a correct manifest entry, no image is built and the plugin cannot be deployed.

**Independent Test**: Add the XKCD plugin entry to `plugins.yaml`, push to `main`, and confirm the tagged image appears in GHCR with correct OCI labels and multi-arch support.

**Acceptance Scenarios**:

1. **Given** `plugins.yaml` contains an entry for `xkcd` source plugin at the target version, **When** CI runs on the `main` branch, **Then** a multi-arch OCI image (`linux/amd64` + `linux/arm64`) is pushed to `ghcr.io/<org>/cloudquery-plugin-xkcd:<version>` with correct OCI labels matching the manifest entry.
2. **Given** the XKCD plugin entry in the manifest specifies the upstream repo as `https://github.com/infobloxopen/cloudquery`, the correct git tag, and the matching commit SHA, **When** CI validates the manifest, **Then** all upstream references resolve successfully and validation passes.
3. **Given** the XKCD plugin image is published, **When** the smoke test runs, **Then** the container starts and the gRPC port accepts connections within 30 seconds.

---

### User Story 2 — Platform engineer deploys XKCD plugin image and syncs comic data to a destination (Priority: P2)

As a **platform engineer**, I pull the published XKCD plugin image and deploy it to Kubernetes so that my CloudQuery sync jobs can connect via `registry: grpc` and sync XKCD comic data (the `xkcd_comics` table) to a supported destination such as PostgreSQL or S3.

**Why this priority**: This validates that the built image actually works end-to-end — the plugin starts as a gRPC server, CloudQuery CLI can connect, and comic data flows to a destination. Without this, the image is untested in a real sync scenario.

**Independent Test**: Deploy the XKCD plugin image to a Kubernetes cluster (or Kind), configure a CloudQuery sync job with `registry: grpc` pointing to the plugin, and verify that the `xkcd_comics` table is populated with comic data in the destination.

**Acceptance Scenarios**:

1. **Given** a published XKCD plugin image, **When** I run the container with no arguments, **Then** the plugin starts a gRPC server listening on `0.0.0.0:7777` and the process runs as a non-root user.
2. **Given** a running XKCD plugin container in Kubernetes, **When** a CloudQuery sync job references it via `registry: grpc` and `path: <service>:7777` with `tables: ["xkcd_comics"]`, **Then** the sync completes successfully and comic records appear in the destination.
3. **Given** a Kubernetes `SecurityContext` with `readOnlyRootFilesystem: true`, `runAsNonRoot: true`, and all capabilities dropped, **When** the XKCD plugin container starts, **Then** it runs without error.
4. **Given** the `xkcd_comics` table is synced, **When** I inspect the destination data, **Then** each record contains the expected comic fields: num (primary key), title, safe_title, alt text, image URL, transcript, publication date (year, month, day), link, and news.

---

### User Story 3 — Operator syncs XKCD comics incrementally using backend state (Priority: P3)

As an **operator**, I configure the XKCD sync with a backend (state store) so that subsequent syncs only fetch new comics published since the last sync, reducing API calls and sync duration.

**Why this priority**: Incremental sync is an important operational efficiency. The XKCD API has over 3,000 comics; re-fetching all of them on every sync is wasteful. The upstream plugin already supports state-backed incremental sync.

**Independent Test**: Run two consecutive syncs with a backend configured. Verify the second sync only fetches comics published after the first sync.

**Acceptance Scenarios**:

1. **Given** a first sync completes and syncs all comics up to comic N, **When** a second sync runs with the same backend configuration, **Then** only comics numbered greater than N are fetched from the XKCD API.
2. **Given** a backend state store is configured, **When** the sync completes, **Then** the state records the highest comic number synced.
3. **Given** no backend is configured, **When** a sync runs, **Then** all comics are fetched (full sync), and the sync completes without error.

---

### User Story 4 — Operator uses Kubernetes example manifests to deploy the XKCD plugin (Priority: P4)

As an **operator**, I use the provided Kubernetes example manifests to deploy the XKCD plugin as a gRPC server and run a CloudQuery sync job, so I can get started quickly without writing manifests from scratch.

**Why this priority**: Example manifests accelerate adoption and provide a validated reference configuration. They are documentation deliverables, not core functionality.

**Independent Test**: Apply the example manifests to a Kubernetes cluster and verify the sync job completes successfully.

**Acceptance Scenarios**:

1. **Given** the example Kubernetes manifests exist under `examples/xkcd/`, **When** I apply them to a cluster, **Then** a Deployment + Service for the XKCD plugin gRPC server and a sync Job are created.
2. **Given** the example CloudQuery configuration references the XKCD plugin via `registry: grpc`, **When** the sync job runs, **Then** it connects to the XKCD plugin gRPC server and syncs the `xkcd_comics` table.

---

### Edge Cases

- What happens when the XKCD API is temporarily unavailable during a sync? — The plugin retries failed HTTP requests according to its internal retry logic; individual comic fetch failures are logged but do not halt the entire sync (the upstream plugin logs errors and continues).
- What happens when comic #404 is requested? — The XKCD API intentionally returns a 404 for comic number 404 (as an Easter egg). The sync logic must skip comic #404 explicitly to avoid false errors.
- What happens when a new XKCD comic is published between two incremental syncs? — The next sync picks it up via the state-backed cursor (highest comic number).
- What happens when the concurrency setting is set to an invalid value (zero or negative)? — The plugin defaults to a concurrency of 10 when the value is less than 1.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The `plugins.yaml` manifest MUST contain a new entry for the XKCD source plugin specifying: kind (`source`), name (`xkcd`), version (matching a released upstream tag), upstream repo (`https://github.com/infobloxopen/cloudquery`), upstream git tag (e.g., `plugins-source-xkcd-v1.5.33`), upstream commit SHA, and build configuration (plugin directory path, Go version, ldflags version path).
- **FR-002**: The manifest entry MUST specify the correct `plugin_dir` as `plugins/source/xkcd` and the correct `ldflags_version_path` to inject the version string into the plugin binary at build time.
- **FR-003**: The built OCI image MUST expose a single table, `xkcd_comics`, with the following columns: `num` (primary key, int64), `month` (utf8), `link` (utf8), `year` (utf8), `news` (utf8), `safe_title` (utf8), `transcript` (utf8), `alt` (utf8), `img` (utf8), `title` (utf8), `day` (utf8), plus CloudQuery internal columns (`_cq_id`, `_cq_parent_id`).
- **FR-004**: The plugin MUST fetch comic data from the public XKCD JSON API (`https://xkcd.com/{num}/info.0.json` for specific comics, `https://xkcd.com/info.0.json` for the latest comic) without requiring any authentication.
- **FR-005**: The plugin MUST support configurable concurrency via the `spec.concurrency` field, defaulting to 10 concurrent fetches.
- **FR-006**: The plugin MUST support incremental sync via CloudQuery state/backend mechanism, tracking the highest comic number synced and only fetching newer comics on subsequent syncs.
- **FR-007**: The plugin MUST skip comic #404 during sync, as the XKCD API intentionally returns a 404 HTTP status for that comic number.
- **FR-008**: The plugin MUST support sharding (distributing work across multiple sync instances) as provided by the upstream plugin sharding support.
- **FR-009**: Kubernetes example manifests MUST be provided under `examples/xkcd/` including: a `deployment.yaml` (Deployment + Service for the XKCD plugin gRPC server), a `sync-job.yaml` (CloudQuery Job referencing the plugin via `registry: grpc`), and a `cloudquery.yaml` (CloudQuery source + destination configuration).
- **FR-010**: The `build-index.md` and `build-index.json` MUST be updated to include the XKCD plugin image entry after a successful build on `main`.

### Key Entities

- **XKCD Comic**: A single comic record fetched from the XKCD API. Key attributes: num (unique identifier), title, safe_title (URL-safe title), alt (hover text), img (image URL), transcript, publication date (year, month, day), link, news.
- **Plugin Manifest Entry**: The YAML block in `plugins.yaml` that declares the XKCD source plugin. Key attributes: name, kind, version, upstream repo/tag/commit, build configuration.
- **Sync State**: The cursor record stored in the backend that tracks the highest comic number synced, enabling incremental sync.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The XKCD source plugin image is published to GHCR as a multi-arch image after merging the manifest entry to `main`.
- **SC-002**: A CloudQuery sync using the published XKCD plugin image via `registry: grpc` successfully populates the `xkcd_comics` table with at least 3,000 comic records on a full sync.
- **SC-003**: An incremental sync (second run with backend configured) completes in under 30 seconds when no new comics have been published since the last sync.
- **SC-004**: The XKCD plugin image passes the existing smoke test: container starts and gRPC port accepts connections within 30 seconds.
- **SC-005**: Adding the XKCD plugin to the manifest requires editing only `plugins.yaml` — no workflow, Dockerfile, or script changes.
- **SC-006**: The Kubernetes example manifests deploy successfully and a sync job completes end-to-end using `registry: grpc`.
- **SC-007**: The synced `xkcd_comics` data does not contain a record for comic #404.

## Assumptions

- The existing CI pipeline (established in feature 001-oci-image-pipeline) is fully operational and can build source plugins using the same manifest-driven approach used for destination plugins.
- The upstream XKCD source plugin at `plugins/source/xkcd` in the `cloudquery/cloudquery` repository is publicly accessible and licensed under a compatible open-source license (MPL-2.0).
- The XKCD API (`https://xkcd.com/json.html`) remains publicly available without authentication and maintains its current JSON response format.
- The `ldflags_version_path` for the XKCD plugin follows the pattern `github.com/cloudquery/cloudquery/plugins/source/xkcd/plugin.Version` (consistent with the upstream `plugin/plugin.go` which defines `Version = "development"`).
- The Go version required to build the XKCD plugin can be determined from the upstream `go.mod` file and will match or be compatible with the version used for existing plugins in the manifest.
- The existing Kubernetes example structure (Deployment, Service, sync Job, CloudQuery config) established for destination plugins applies equally to source plugins with minimal adaptation (source plugins also expose gRPC on port 7777).
