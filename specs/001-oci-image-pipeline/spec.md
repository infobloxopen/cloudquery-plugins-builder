# Feature Specification: OCI Image Pipeline for CloudQuery Plugins

**Feature Branch**: `001-oci-image-pipeline`
**Created**: 2026-02-12
**Status**: Draft
**Input**: User description: "Build a GitHub repository that automatically builds and publishes OCI images to GHCR for selected CloudQuery plugins so they can be pulled and run in Kubernetes without requiring CloudQuery Hub authentication."

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Operator pins plugin versions and gets images in GHCR (Priority: P1)

As an **operator**, I define the plugins and versions I need in a single manifest file so that CI automatically builds multi-architecture OCI images and publishes them to GHCR, giving me deterministic, pull-ready images without any CloudQuery Hub authentication.

**Why this priority**: This is the foundational value proposition — without published images nothing else works. It covers the manifest, the build, the publish, and the tagging contract.

**Independent Test**: Edit `plugins.yaml` to list a single plugin/version, push to `main`, and confirm the tagged image appears in GHCR with correct OCI labels and multi-arch support.

**Acceptance Scenarios**:

1. **Given** `plugins.yaml` contains an entry for `cloudquery/postgresql` destination plugin v8.14.1, **When** CI runs on the `main` branch, **Then** a multi-arch OCI image (`linux/amd64` + `linux/arm64`) is pushed to `ghcr.io/<org>/cloudquery-plugin-postgresql:<version>` and a digest-pinned reference is recorded.
2. **Given** a successfully pushed image, **When** I inspect its OCI labels, **Then** I find `org.opencontainers.image.source`, `org.opencontainers.image.revision`, `org.opencontainers.image.created`, `io.cloudquery.plugin.upstream-repo`, `io.cloudquery.plugin.upstream-tag`, and `io.cloudquery.plugin.upstream-commit` — all non-empty and matching the manifest entry.
3. **Given** a successfully pushed image, **When** I inspect the GHCR artifact metadata, **Then** an SBOM attestation, a SLSA provenance attestation, and a cosign signature (keyless / OIDC) are present.
4. **Given** `plugins.yaml` lists three plugins (s3 v7.10.2, file v5.5.1, postgresql v8.14.1), **When** CI runs, **Then** all three images are built and pushed — one failure does not block the others (matrix strategy with independent jobs).

---

### User Story 2 — Platform engineer deploys plugin images to Kubernetes (Priority: P2)

As a **platform engineer**, I pull the published image and deploy it to Kubernetes as a gRPC server so that my CloudQuery sync jobs can connect via `registry: grpc` instead of downloading from CloudQuery Hub.

**Why this priority**: This validates the runtime contract (gRPC on port 7777, non-root, read-only rootfs) and proves the images are useful in a real Kubernetes environment.

**Independent Test**: Deploy the postgresql plugin image to a Kubernetes cluster (or Kind), verify the gRPC port is reachable from a CloudQuery job pod, and run a minimal sync.

**Acceptance Scenarios**:

1. **Given** a published image for the postgresql plugin, **When** I run the container with no arguments, **Then** the plugin starts a gRPC server listening on `0.0.0.0:7777` and the process runs as a non-root user.
2. **Given** a running plugin container in k8s, **When** a CloudQuery sync job references it via `registry: grpc` and `path: <service>:7777`, **Then** the sync completes successfully for a trivial table.
3. **Given** a Kubernetes `SecurityContext` with `readOnlyRootFilesystem: true`, `runAsNonRoot: true`, and all capabilities dropped, **When** the plugin container starts, **Then** it runs without error (writable scratch space, if needed, is provided via an `emptyDir` volume).
4. **Given** the container is started with environment variable `CQ_PLUGIN_PORT=9090`, **When** I connect on port 9090, **Then** the gRPC server responds.

---

### User Story 3 — Maintainer adds a new plugin or version via manifest edit (Priority: P3)

As a **maintainer**, I add a new plugin (or a new version of an existing plugin) by editing a single YAML block in `plugins.yaml` so that CI picks it up automatically without any workflow file changes.

**Why this priority**: This validates the scalability and developer experience of the manifest-driven design. Without it, the project becomes a maintenance burden.

**Independent Test**: Add a new entry (e.g., a hypothetical `cloudquery/csv` destination plugin) to `plugins.yaml`, open a PR, and confirm CI validates the entry, builds the image, and runs the smoke test — all without touching any workflow file.

**Acceptance Scenarios**:

1. **Given** I add a new plugin entry to `plugins.yaml`, **When** I open a pull request, **Then** CI validates the manifest schema, verifies the upstream git tag exists, builds the image (without pushing), and runs the smoke test.
2. **Given** a valid PR that adds a new plugin version, **When** it is merged to `main`, **Then** CI builds and pushes only the new/changed images (unchanged images are not rebuilt unnecessarily).
3. **Given** a PR where the upstream tag does not exist, **When** CI runs, **Then** the manifest validation step fails with a clear error message identifying the invalid entry.

---

### User Story 4 — Consumer discovers available images via build index (Priority: P4)

As a **consumer** (human or automation), I consult a machine-readable build index to discover which plugin images are available, their digests, and their upstream provenance so I can automate my deployment manifests.

**Why this priority**: Build tracking is a transparency/compliance requirement but not strictly needed for core functionality.

**Independent Test**: After a successful `main` build, download the build index artifact and verify its schema; also check that `docs/build-index.md` has been updated.

**Acceptance Scenarios**:

1. **Given** a successful CI run on `main`, **When** I download the `build-index.json` workflow artifact, **Then** it contains a JSON array where each entry has: `plugin_kind`, `plugin_name`, `version`, `image`, `digest`, `upstream_repo`, `upstream_tag`, `upstream_commit`, `build_timestamp`, and `ci_run_url`.
2. **Given** a successful CI run on `main`, **When** I open `docs/build-index.md` in the repository, **Then** a Markdown table lists every published image with its version, digest, and upstream commit — updated within the same commit or workflow run.

---

### User Story 5 — PR author gets fast feedback on manifest and image quality (Priority: P5)

As a **PR author**, I receive automated feedback on my manifest changes within the pull request so I can iterate quickly without waiting for a full publish cycle.

**Why this priority**: Good DX and shift-left validation, but the pipeline works without it (just with worse feedback loops).

**Independent Test**: Open a PR with a deliberately invalid manifest entry and confirm CI fails with actionable error messages before any image build starts.

**Acceptance Scenarios**:

1. **Given** a PR that modifies `plugins.yaml`, **When** CI runs, **Then** the following checks execute in order: manifest schema validation → upstream ref verification → image build (no push) → smoke test (container starts, port 7777 accepts connections within 30 seconds).
2. **Given** a PR with a malformed `plugins.yaml` (e.g., missing required field), **When** CI runs, **Then** the schema validation step fails with a message identifying the exact field and line.
3. **Given** a PR where the image builds successfully, **When** the smoke test runs, **Then** CI starts the container, waits up to 30 seconds for port 7777 to accept a TCP connection, and reports pass/fail.

---

### Edge Cases

- What happens when an upstream plugin repository is temporarily unavailable during CI? — CI retries the git clone/fetch up to 3 times with exponential backoff; if still failing, the job fails with a clear "upstream unavailable" message and does not block other plugins in the matrix.
- What happens when a plugin requires a writable directory at runtime? — The Dockerfile documents the required writable path (e.g., `/tmp`); Kubernetes examples include an `emptyDir` volume mount for that path.
- What happens when GHCR is rate-limited or down during a push? — CI retries the push with standard Docker/ORAS retry logic; the job fails gracefully if retries are exhausted.
- What happens when two PRs update `plugins.yaml` concurrently? — Standard Git merge conflict resolution applies; CI re-runs on the merge commit.
- What happens when a new Go version is needed to build a plugin? — The Go version is pinned in the Dockerfile (per the reproducibility article); the maintainer updates the pin as part of the manifest change or a dedicated PR.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The repository MUST contain a manifest file (`plugins.yaml`) at the repository root that declaratively lists every plugin to build, including: plugin kind (`source` or `destination`), plugin name, version, upstream repository URL, upstream git tag, upstream commit SHA, and any plugin-specific build arguments.
- **FR-002**: The manifest MUST support multiple versions of the same plugin (e.g., postgresql v8.14.1 and postgresql v8.15.0 simultaneously).
- **FR-003**: A JSON Schema for the manifest MUST exist in the repository and MUST be validated by CI before any build step.
- **FR-004**: CI MUST generate a build matrix from the manifest; no per-plugin workflow files are permitted.
- **FR-005**: CI MUST build multi-architecture OCI images (`linux/amd64` and `linux/arm64`) for every manifest entry.
- **FR-006**: Images MUST be tagged with at least the plugin version (e.g., `ghcr.io/<org>/cloudquery-plugin-<name>:<version>`). Digest-pinned references MUST be recorded in the build index.
- **FR-007**: Every image MUST carry the OCI labels defined in Constitution Article II (source repo, revision, created timestamp, upstream repo, upstream tag, upstream commit).
- **FR-008**: Every pushed image MUST have an attached SBOM (SPDX or CycloneDX), a SLSA provenance attestation, and a cosign keyless signature (GitHub OIDC).
- **FR-009**: The default image entrypoint MUST start the plugin as a gRPC server listening on `0.0.0.0:7777`.
- **FR-010**: The listen address and port MUST be overridable via CLI arguments (`--address`, `--port`) and/or environment variables (`CQ_PLUGIN_ADDRESS`, `CQ_PLUGIN_PORT`).
- **FR-011**: Images MUST run as a non-root user (UID ≥ 1000), with a read-only root filesystem, and with all Linux capabilities dropped.
- **FR-012**: CI MUST produce a `build-index.json` artifact on every workflow run containing: plugin kind, name, version, image reference, digest(s), upstream repo, upstream tag, upstream commit, build timestamp, and CI run URL.
- **FR-013**: A human-readable `docs/build-index.md` MUST be maintained and updated on every release to `main`.
- **FR-014**: PR CI MUST validate manifest schema, verify upstream tags exist, build images without pushing, and run a smoke test (container starts + port 7777 accepts TCP connections within 30 seconds).
- **FR-015**: The repository MUST include Kubernetes example manifests for each plugin: a Deployment + Service for the plugin gRPC server, and a CloudQuery Job or CronJob that references the plugin via `registry: grpc`.
- **FR-016**: The repository MUST provide a Makefile or scripts to build a specific plugin version locally for debugging purposes.
- **FR-017**: Images MUST be pushed to GHCR only from the `main` branch and only after all CI checks pass.
- **FR-018**: The final image stage MUST be minimal (distroless or Alpine-based) and MUST NOT include a shell or package manager unless explicitly justified and documented.
- **FR-019**: CI workflows MUST pin all third-party actions to full commit SHAs and MUST set `permissions` following least-privilege.
- **FR-020**: The repository MUST NOT include any mechanism to fetch closed-source or premium plugin binaries, bypass authentication, or rehost proprietary artifacts.

### Key Entities

- **Plugin Manifest Entry**: Represents a single plugin/version to build. Key attributes: kind (source/destination), name, version, upstream repo URL, upstream git tag, upstream commit SHA, build args.
- **OCI Image**: The built container image published to GHCR. Key attributes: repository path, tag, digest, architecture, OCI labels, attestations.
- **Build Index Record**: A provenance record tying a manifest entry to its published image. Key attributes: plugin kind, name, version, image reference, digest, upstream commit, build timestamp, CI run URL.
- **Kubernetes Example Set**: Per-plugin deployment templates. Key attributes: Deployment, Service, Job/CronJob manifests referencing the plugin image and gRPC address.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All three MVP plugins (s3 v7.10.2, file v5.5.1, postgresql v8.14.1) have published multi-arch images in GHCR within the first successful `main` build.
- **SC-002**: Adding a new plugin version to the manifest requires editing only `plugins.yaml` — no workflow, Dockerfile, or script changes.
- **SC-003**: Every published image passes the smoke test: container starts and gRPC port accepts connections within 30 seconds.
- **SC-004**: Every published image carries a valid SBOM, SLSA provenance attestation, and cosign signature verifiable by a third party.
- **SC-005**: A platform engineer can deploy a plugin image to Kubernetes and successfully complete a CloudQuery sync using `registry: grpc` with zero CloudQuery Hub authentication.
- **SC-006**: The build index artifact is downloadable from every CI run and contains correct provenance data for all built images.
- **SC-007**: PR validation catches an invalid manifest entry (bad schema or nonexistent upstream tag) and fails with a clear, actionable error message within 5 minutes.
- **SC-008**: Images run successfully under a restrictive Kubernetes security context: non-root, read-only rootfs, all capabilities dropped.

## Assumptions

- Upstream CloudQuery plugin repositories (github.com/cloudquery/*) remain publicly accessible and their source code remains licensed under Apache-2.0 or a compatible open-source license.
- GHCR publishing uses the built-in `GITHUB_TOKEN` from GitHub Actions with appropriate `packages: write` permissions; no additional registry credentials are needed.
- CloudQuery CLI supports the `registry: grpc` + `path: <host>:<port>` configuration for connecting to externally-hosted plugin gRPC servers (this is documented CloudQuery functionality).
- The Go toolchain version required to build each plugin can be determined from the upstream `go.mod` file and pinned in the Dockerfile.
- Plugin gRPC server mode is invoked via the `serve` subcommand (e.g., `plugin serve --address 0.0.0.0:7777`); the exact CLI varies per plugin and will be determined during implementation research.
- Multi-arch builds use Docker Buildx with QEMU emulation in GitHub Actions (standard approach).
- The initial image naming convention follows `ghcr.io/<org>/cloudquery-plugin-<name>:<version>`.
