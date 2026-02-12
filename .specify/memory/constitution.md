<!--
  Sync Impact Report
  ==================
  Version change : (none) → 1.0.0 (initial adoption)
  Modified principles: N/A (initial)
  Added sections:
    - Core Principles (7 articles)
    - Coding Conventions
    - Governance
  Removed sections: N/A (initial)
  Templates requiring updates:
    - .specify/templates/plan-template.md        ✅ compatible (Constitution Check is generic)
    - .specify/templates/spec-template.md         ✅ compatible (requirements section is generic)
    - .specify/templates/tasks-template.md        ✅ compatible (phase structure is generic)
    - .specify/templates/checklist-template.md    ✅ compatible (generic checklist)
    - .specify/templates/agent-file-template.md   ✅ compatible (generic guidelines)
  Follow-up TODOs: none
-->

# CloudQuery Plugins Builder Constitution

## Core Principles

### I. Licensing & Redistribution Compliance

All images produced by this repository MUST be built exclusively from
plugin source code that is publicly accessible and licensed for
redistribution (e.g., Apache-2.0, MPL-2.0).

- Contributors MUST NOT scrape, reverse-engineer, or bypass any
  authentication mechanism to obtain proprietary or premium plugin
  binaries.
- Contributors MUST NOT bundle, redistribute, or reference any artifact
  whose license prohibits redistribution.
- Each plugin directory MUST include a copy of (or link to) the upstream
  license notice.
- Published OCI images MUST carry upstream license files at
  `/licenses/` inside the image.

**Rationale**: CloudQuery plugins are open-source, but the Hub
distribution channel has its own terms. This principle ensures the
project stays on the right side of every applicable license.

### II. Reproducibility & Provenance

Every published image MUST be traceable to an immutable upstream
reference.

- Builds MUST pin the upstream plugin source to an exact git tag **and**
  the commit SHA that tag resolves to at build time.
- Dockerfiles MUST NOT use floating tags (e.g., `latest`, `main`) for
  base images or Go module versions; every input MUST be pinned by
  digest or exact version.
- OCI image labels MUST include at minimum:
  - `org.opencontainers.image.source` — this repository's URL
  - `org.opencontainers.image.revision` — this repository's commit SHA
  - `org.opencontainers.image.created` — RFC-3339 build timestamp
  - `io.cloudquery.plugin.upstream-repo` — upstream plugin repo URL
  - `io.cloudquery.plugin.upstream-tag` — upstream git tag
  - `io.cloudquery.plugin.upstream-commit` — upstream commit SHA

**Rationale**: Deterministic builds and rich metadata allow consumers
to audit exactly what is inside an image and reproduce it independently.

### III. Supply Chain Security

Every release artifact MUST be accompanied by provenance and
composition metadata.

- CI MUST generate an SBOM (SPDX or CycloneDX) for every pushed image
  and attach it as an OCI artifact.
- CI MUST generate a SLSA provenance attestation for every pushed image.
- Images MUST be signed with `cosign` using GitHub Actions OIDC
  (keyless); long-lived signing keys are prohibited.
- Base images MUST be minimal (distroless or Alpine-based) and MUST NOT
  include a shell or package manager in the final stage unless
  explicitly justified and documented.
- Final image stages MUST run as a non-root user (UID ≥ 1000).

**Rationale**: Signed, attested, minimal images reduce attack surface
and give downstream consumers a verifiable chain of custody.

### IV. Kubernetes-First Runtime Contract

Plugin images are purpose-built for Kubernetes side-car / standalone
gRPC server deployments.

- The default entrypoint MUST start the plugin as a gRPC server
  listening on `0.0.0.0:7777`.
- The listen address and port MUST be overridable via:
  - CLI arguments (e.g., `--address`, `--port`)
  - Environment variables (e.g., `CQ_PLUGIN_ADDRESS`, `CQ_PLUGIN_PORT`)
- Images MUST be runnable with a **read-only root filesystem**
  (`readOnlyRootFilesystem: true`).
- Images MUST drop all Linux capabilities and MUST NOT require
  privileged mode.
- A `/tmp` or `/data` volume MUST be documented if the plugin needs a
  writable scratch directory.

**Rationale**: Enforcing a strict, predictable runtime contract lets
platform teams deploy plugins via Helm or raw manifests without
per-plugin customisation.

### V. Manifest-Driven & Scalable

A single declarative manifest is the source of truth for which plugins
and versions are built.

- The file `plugins.yaml` (repository root) MUST define every
  plugin/version tuple that CI builds.
- Adding a new plugin or version MUST require editing only
  `plugins.yaml` (and, if needed, a shared Dockerfile template).
- CI MUST generate its build matrix by reading `plugins.yaml`; no
  hard-coded per-plugin workflow files are permitted.
- The manifest schema MUST be documented and validated in CI before any
  build step executes.

**Rationale**: A single manifest prevents drift, reduces copy-paste
errors, and makes scaling to tens of plugins trivial.

### VI. Transparency & Trackability

Every build MUST produce a machine-readable index that maps plugin
metadata to published artifacts.

- CI MUST emit a JSON build index with at minimum:
  `plugin`, `version`, `image`, `digest`, `upstream_repo`,
  `upstream_tag`, `upstream_commit`, `build_timestamp`.
- The build index MUST be published as a GitHub Actions artifact on
  every workflow run.
- A human-readable summary (Markdown table) MUST be maintained in-repo
  (e.g., `docs/build-index.md`) and updated on every release to `main`.

**Rationale**: A published index gives consumers a single place to
discover available images, verify provenance, and automate deployment
manifests.

### VII. Quality Gates

No image may be pushed to GHCR unless it passes the required checks.

- **Manifest validation**: CI MUST validate `plugins.yaml` against its
  JSON Schema before any build step.
- **Upstream ref verification**: CI MUST confirm that every upstream
  git tag and commit SHA in the manifest actually exist in the upstream
  repository.
- **Image build**: The image MUST build without errors.
- **Smoke test**: CI MUST run a container from the built image and
  assert that:
  1. The process starts without error.
  2. The gRPC port (default 7777) is accepting connections within a
     reasonable timeout (≤ 30 s).
- **Push gating**: Images are pushed to GHCR only from the `main`
  branch and only after all preceding checks pass.
- Pull-request checks MUST be required (branch protection); direct
  pushes to `main` are prohibited.

**Rationale**: Automated gates prevent broken or untested images from
reaching consumers and enforce the runtime contract defined in
Article IV.

## Coding Conventions

### GitHub Actions YAML

- Workflows MUST live under `.github/workflows/`.
- Every workflow MUST pin third-party actions to a full commit SHA
  (not a tag).
- Reusable logic MUST be extracted into composite actions or called
  workflows; duplication across workflow files is prohibited.
- Secrets MUST be passed explicitly; `secrets: inherit` is forbidden
  unless scoped to an internal reusable workflow.
- Every workflow MUST set `permissions` at the job or workflow level
  following least-privilege.

### Bash Scripts

- Every script MUST begin with `set -euo pipefail`.
- Scripts MUST pass `shellcheck` with zero warnings.
- Variables MUST be quoted (`"$var"`, not `$var`).
- Scripts MUST NOT exceed 200 lines; extract functions or split files
  when approaching this limit.
- Use `#!/usr/bin/env bash` as the shebang.

### Go Helper Tools

- Go code MUST compile with the latest two stable Go releases.
- Code MUST pass `go vet`, `staticcheck`, and `golangci-lint` with
  the repository's configuration and zero findings.
- Format with `gofmt` (or `goimports`); CI MUST reject unformatted
  code.
- Exported functions MUST have doc comments.

### Python Helper Tools

- Target Python ≥ 3.11.
- Code MUST pass `ruff check` and `ruff format --check` with zero
  findings.
- Type hints are required for all public function signatures.
- Dependencies MUST be pinned in a `requirements.txt` or
  `pyproject.toml` with exact versions.

### Documentation

- Every user-facing change MUST be reflected in the relevant docs
  before the PR is merged.
- Markdown MUST pass `markdownlint` with the repository's
  configuration.
- READMEs MUST include: project purpose, quick-start, manifest
  reference, and contribution guide.
- Architecture Decision Records (ADRs) MUST be created in `docs/adr/`
  for any decision that materially affects build pipeline, image
  layout, or runtime contract.

## Governance

This constitution is the highest-authority document in the repository.
All design decisions, pull requests, and code reviews MUST demonstrate
compliance with the principles above.

- **Amendments** require a pull request that:
  1. Clearly states the motivation for the change.
  2. Updates this document.
  3. Propagates changes to affected templates, CI workflows, and docs.
  4. Is approved by at least one code owner.
- **Versioning** follows Semantic Versioning:
  - MAJOR — removal or incompatible redefinition of a principle.
  - MINOR — new principle, section, or materially expanded guidance.
  - PATCH — clarifications, typo fixes, non-semantic refinements.
- **Compliance reviews**: every pull request description MUST include a
  brief note confirming which principles were considered and how
  compliance is maintained.

**Version**: 1.0.0 | **Ratified**: 2026-02-12 | **Last Amended**: 2026-02-12
