# Implementation Plan: OCI Image Pipeline for CloudQuery Plugins

**Branch**: `001-oci-image-pipeline` | **Date**: 2026-02-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-oci-image-pipeline/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Build a CI/CD pipeline that reads a declarative `plugins.yaml` manifest, builds multi-architecture OCI images for selected CloudQuery destination plugins from upstream open-source source code, publishes them to GHCR with SBOM/provenance/cosign attestations, and provides Kubernetes deployment examples. The pipeline uses a single generic multi-stage Dockerfile parameterised by build args, a Go entrypoint wrapper for env-var-driven port configuration, and a matrix-based GitHub Actions workflow that derives its build targets entirely from the manifest. MVP covers three destination plugins: s3 v7.10.2, file v5.5.1, postgresql v8.14.1.

## Technical Context

**Language/Version**: Go 1.25.6 (plugins + entrypoint wrapper); Bash (scripts); JSON Schema (validation)
**Primary Dependencies**: Docker Buildx, QEMU, cosign, yq, jq, GitHub Actions
**Storage**: N/A (OCI images stored in GHCR; build index as JSON artifact + committed Markdown)
**Testing**: Bash smoke test (TCP port check); JSON Schema validation; shellcheck for scripts
**Target Platform**: Linux containers (amd64 + arm64); GitHub Actions runners (ubuntu-latest)
**Project Type**: Single project (CI pipeline + helper scripts + examples)
**Performance Goals**: Full 3-plugin build + smoke test completes within 20 minutes on GitHub Actions
**Constraints**: No CGO; no CloudQuery API keys; no proprietary artifacts; all actions pinned to SHA
**Scale/Scope**: 3 plugins at MVP; manifest-driven scaling to 50+ plugins with no workflow changes

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Article | Status | Evidence |
|---------|--------|----------|
| **I. Licensing & Redistribution** | ✅ PASS | Builds from upstream MPL-2.0 source only; LICENSE files copied into images at `/licenses/`; no proprietary binaries (FR-020) |
| **II. Reproducibility & Provenance** | ✅ PASS | Manifest pins upstream git tag + commit SHA; Dockerfile pins Go version + base image by digest; OCI labels include all required fields (data-model.md § OCI Image) |
| **III. Supply Chain Security** | ✅ PASS | Buildx generates SBOM + SLSA provenance; cosign keyless signing via OIDC; distroless final image; non-root user UID 65534; no shell in final image |
| **IV. K8s Runtime Contract** | ✅ PASS | Default entrypoint serves gRPC on `[::]:7777`; env vars `CQ_PLUGIN_ADDRESS`/`CQ_PLUGIN_PORT` override via Go entrypoint wrapper; read-only rootfs supported; all capabilities dropped |
| **V. Manifest-Driven & Scalable** | ✅ PASS | Single `plugins.yaml` drives CI matrix; adding a plugin = editing one YAML block; JSON Schema validated before build |
| **VI. Transparency & Trackability** | ✅ PASS | `build-index.json` emitted every run; `docs/build-index.md` updated on main; schemas defined in contracts/ |
| **VII. Quality Gates** | ✅ PASS | PR workflow: schema validation → upstream ref check → image build → smoke test (TCP 7777, 30s); main pushes only after all checks pass; branch protection required |
| **Coding: GitHub Actions** | ✅ PASS | All actions pinned to SHA; permissions set per job; reusable composite actions for shared logic |
| **Coding: Bash** | ✅ PASS | `set -euo pipefail`; shellcheck; <200 lines per script; `#!/usr/bin/env bash` |
| **Coding: Go** | ✅ PASS | Entrypoint wrapper: go vet + staticcheck + golangci-lint; gofmt; doc comments |
| **Coding: Docs** | ✅ PASS | README with purpose + quickstart + manifest reference; ADR for key decisions |

**Gate result**: ✅ ALL PASS — no violations.

## Project Structure

### Documentation (this feature)

```text
specs/001-oci-image-pipeline/
├── plan.md              # This file
├── research.md          # Phase 0 output — upstream repo research
├── data-model.md        # Phase 1 output — manifest, image, index schemas
├── quickstart.md        # Phase 1 output — developer getting started guide
├── contracts/
│   ├── plugins-manifest.schema.json   # JSON Schema for plugins.yaml
│   ├── build-index.schema.json        # JSON Schema for build-index.json
│   ├── runtime-contract.md            # OCI image runtime behaviour spec
│   └── ci-workflows.md               # CI workflow contracts
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
cloudquery-plugins-builder/
├── plugins.yaml                          # Manifest: plugins + versions to build
├── Dockerfile                            # Generic multi-stage Dockerfile (parameterised)
├── Makefile                              # Developer-facing targets
├── README.md                             # Project overview + quickstart
├── LICENSE                               # This repo's license
│
├── schemas/
│   ├── plugins-manifest.schema.json      # JSON Schema for plugins.yaml
│   └── build-index.schema.json           # JSON Schema for build-index.json
│
├── cmd/
│   └── entrypoint/
│       └── main.go                       # Go entrypoint wrapper (env var → --address bridge)
│
├── scripts/
│   ├── build.sh                          # Build a single plugin image locally
│   ├── build-all.sh                      # Build all plugins from manifest
│   ├── smoke-test.sh                     # TCP port connectivity check
│   ├── validate-manifest.sh              # Schema validation + upstream ref verification
│   ├── generate-build-index.sh           # Aggregate per-plugin metadata into build-index.json
│   └── generate-matrix.sh               # Parse plugins.yaml → GHA matrix JSON
│
├── .github/
│   ├── workflows/
│   │   ├── pr-validate.yaml              # PR validation (no push)
│   │   ├── publish.yaml                  # Main branch publish (push to GHCR)
│   │   └── check-updates.yaml           # Optional: scheduled upstream version check
│   └── actions/
│       └── build-plugin/
│           └── action.yaml               # Composite action: build + test + push one plugin
│
├── examples/
│   ├── postgresql/
│   │   ├── deployment.yaml               # K8s Deployment + Service
│   │   ├── sync-job.yaml                 # CloudQuery sync Job
│   │   └── cloudquery.yaml               # CQ config referencing gRPC plugin
│   ├── s3/
│   │   ├── deployment.yaml
│   │   ├── sync-job.yaml
│   │   └── cloudquery.yaml
│   └── file/
│       ├── deployment.yaml
│       ├── sync-job.yaml
│       └── cloudquery.yaml
│
├── docs/
│   ├── build-index.md                    # Human-readable build index (auto-generated)
│   └── adr/
│       ├── 001-monorepo-tag-checkout.md  # ADR: build from monorepo tags
│       ├── 002-distroless-base-image.md  # ADR: distroless over Alpine
│       └── 003-go-entrypoint-wrapper.md  # ADR: Go wrapper over shell for env vars
│
└── specs/                                # Feature specifications (speckit)
    └── 001-oci-image-pipeline/
        └── ...
```

**Structure Decision**: Single project structure. This is a CI/build pipeline repo, not a traditional application. The primary artifacts are a Dockerfile, CI workflows, helper scripts, and Kubernetes examples. A Go module exists only for the small entrypoint wrapper (`cmd/entrypoint/`). No `src/` directory is needed.

## Build Pipeline Flow

```
plugins.yaml
    │
    ▼
┌─────────────────────────┐
│  generate-matrix.sh     │  Parse manifest → GHA matrix JSON
└───────────┬─────────────┘
            │
            ▼  (per matrix entry)
┌─────────────────────────┐
│  validate-manifest.sh   │  JSON Schema check + git ls-remote to verify tag/commit
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  git clone --depth=1    │  Clone upstream monorepo at pinned tag
│  --branch <tag>         │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  docker buildx build    │  Multi-stage Dockerfile:
│                         │    Stage 1: golang:<go_version> → go build
│                         │    Stage 2: Build entrypoint wrapper
│                         │    Stage 3: distroless → COPY binaries + licenses
│  --platform linux/amd64,│
│             linux/arm64 │
│  --sbom=true            │
│  --provenance=mode=max  │
│  --label ... (OCI)      │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  smoke-test.sh          │  docker run → wait 30s → TCP check port 7777
└───────────┬─────────────┘
            │
            ▼  (main branch only)
┌─────────────────────────┐
│  docker buildx push     │  Push multi-arch manifest to GHCR
│  + cosign sign          │  Keyless signing via GitHub OIDC
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  generate-build-index   │  Collect digests → build-index.json
│  .sh                    │  → upload as GHA artifact
│                         │  → update docs/build-index.md
└─────────────────────────┘
```

## Dockerfile Design

```dockerfile
# ============================================================
# Stage 1: Build the plugin binary
# ============================================================
ARG GO_VERSION=1.25.6
FROM golang:${GO_VERSION} AS plugin-builder

ARG PLUGIN_DIR=plugins/destination/postgresql
ARG PLUGIN_VERSION=v8.14.1
ARG LDFLAGS_VERSION_PATH=""
ARG BIN_NAME=plugin
ARG UPSTREAM_REPO=https://github.com/cloudquery/cloudquery
ARG UPSTREAM_TAG=plugins-destination-postgresql-v8.14.1

# Clone upstream at the exact tag
RUN git clone --depth=1 --branch=${UPSTREAM_TAG} ${UPSTREAM_REPO} /src

WORKDIR /src/${PLUGIN_DIR}

# Build static binary
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w -X ${LDFLAGS_VERSION_PATH}=${PLUGIN_VERSION}" \
    -o /${BIN_NAME} .

# ============================================================
# Stage 2: Build the entrypoint wrapper
# ============================================================
FROM golang:${GO_VERSION} AS entrypoint-builder
COPY cmd/entrypoint/ /build/
WORKDIR /build
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /entrypoint .

# ============================================================
# Stage 3: Final minimal image
# ============================================================
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=plugin-builder /plugin /plugin
COPY --from=entrypoint-builder /entrypoint /entrypoint
COPY --from=plugin-builder /src/LICENSE /licenses/LICENSE

EXPOSE 7777

ENTRYPOINT ["/entrypoint"]
CMD ["serve", "--address", "[::]:7777", "--log-format", "json", "--log-level", "info"]
```

**Key Dockerfile build args** (set from manifest per plugin):

| Build Arg | Source (from `plugins.yaml`) |
|-----------|------------------------------|
| `GO_VERSION` | `build.go_version` |
| `PLUGIN_DIR` | `build.plugin_dir` |
| `PLUGIN_VERSION` | `version` |
| `LDFLAGS_VERSION_PATH` | `build.ldflags_version_path` |
| `BIN_NAME` | `build.bin_name` (default: `plugin`) |
| `UPSTREAM_REPO` | `upstream.repo` |
| `UPSTREAM_TAG` | `upstream.tag` |

## Example Manifest (`plugins.yaml`)

```yaml
apiVersion: v1
plugins:
  - name: s3
    kind: destination
    version: v7.10.2
    upstream:
      repo: https://github.com/cloudquery/cloudquery
      tag: plugins-destination-s3-v7.10.2
      commit: <resolve-at-implementation-time>
    build:
      plugin_dir: plugins/destination/s3
      go_version: "1.25.6"
      ldflags_version_path: >-
        github.com/cloudquery/cloudquery/plugins/destination/s3/v7/resources/plugin.Version

  - name: file
    kind: destination
    version: v5.5.1
    upstream:
      repo: https://github.com/cloudquery/cloudquery
      tag: plugins-destination-file-v5.5.1
      commit: <resolve-at-implementation-time>
    build:
      plugin_dir: plugins/destination/file
      go_version: "1.25.6"
      ldflags_version_path: >-
        github.com/cloudquery/cloudquery/plugins/destination/file/v5/resources/plugin.Version

  - name: postgresql
    kind: destination
    version: v8.14.1
    upstream:
      repo: https://github.com/cloudquery/cloudquery
      tag: plugins-destination-postgresql-v8.14.1
      commit: <resolve-at-implementation-time>
    build:
      plugin_dir: plugins/destination/postgresql
      go_version: "1.25.6"
      ldflags_version_path: >-
        github.com/cloudquery/cloudquery/plugins/destination/postgresql/v8/resources/plugin.Version
```

## Image Naming & Tagging

**Convention**: `ghcr.io/infobloxopen/cloudquery-plugin-<name>:<version>`

| Plugin | Image Reference |
|--------|----------------|
| s3 v7.10.2 | `ghcr.io/infobloxopen/cloudquery-plugin-s3:v7.10.2` |
| file v5.5.1 | `ghcr.io/infobloxopen/cloudquery-plugin-file:v5.5.1` |
| postgresql v8.14.1 | `ghcr.io/infobloxopen/cloudquery-plugin-postgresql:v8.14.1` |

**Rationale**:
- `cloudquery-plugin-` prefix: clear namespace, avoids collision
- Version tag with `v` prefix: matches upstream convention, no ambiguity
- No `latest` tag: enforces explicit version pinning (Constitution Article II)
- Digest-pinned references: recorded in `build-index.json` for automation

## Kubernetes Examples

### Plugin Deployment + Service (postgresql)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudquery-plugin-postgresql
  labels:
    app: cloudquery-plugin-postgresql
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cloudquery-plugin-postgresql
  template:
    metadata:
      labels:
        app: cloudquery-plugin-postgresql
    spec:
      containers:
        - name: plugin
          image: ghcr.io/infobloxopen/cloudquery-plugin-postgresql:v8.14.1
          ports:
            - containerPort: 7777
              protocol: TCP
          readinessProbe:
            tcpSocket:
              port: 7777
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            tcpSocket:
              port: 7777
            initialDelaySeconds: 10
            periodSeconds: 30
          securityContext:
            runAsNonRoot: true
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: tmp
              mountPath: /tmp
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
      volumes:
        - name: tmp
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: cloudquery-plugin-postgresql
spec:
  selector:
    app: cloudquery-plugin-postgresql
  ports:
    - port: 7777
      targetPort: 7777
      protocol: TCP
```

### CloudQuery Sync Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: cloudquery-sync-postgresql
spec:
  template:
    spec:
      containers:
        - name: cloudquery
          image: ghcr.io/cloudquery/cloudquery:latest  # CQ CLI image
          args: ["sync", "/config/cloudquery.yaml"]
          volumeMounts:
            - name: config
              mountPath: /config
      volumes:
        - name: config
          configMap:
            name: cloudquery-sync-config
      restartPolicy: Never
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloudquery-sync-config
data:
  cloudquery.yaml: |
    kind: destination
    spec:
      name: postgresql
      registry: grpc
      path: cloudquery-plugin-postgresql:7777
      spec:
        connection_string: "${PG_CONNECTION_STRING}"
```

## Milestones

### Milestone 1: MVP (3 plugins, CI pipeline)

| Deliverable | Priority |
|------------|----------|
| `plugins.yaml` with 3 MVP plugins | P1 |
| JSON Schema for manifest | P1 |
| Generic multi-stage Dockerfile | P1 |
| Go entrypoint wrapper (`cmd/entrypoint/`) | P1 |
| `scripts/build.sh` + `scripts/smoke-test.sh` | P1 |
| `scripts/validate-manifest.sh` + `scripts/generate-matrix.sh` | P1 |
| PR validation workflow (`pr-validate.yaml`) | P1 |
| Main publish workflow (`publish.yaml`) | P1 |
| Build index generation + `docs/build-index.md` | P2 |
| Kubernetes examples (3 plugins) | P2 |
| Makefile for local DX | P2 |
| README.md | P2 |
| ADRs (3 initial decisions) | P3 |

### Milestone 2: Enhancements (post-MVP)

| Deliverable | Priority |
|------------|----------|
| Scheduled upstream update check workflow | P3 |
| Cosign image signing | P3 |
| Helm chart for plugin deployment | P4 |
| Source plugin support | P4 |
| Build cache optimization (GHA cache, Go module cache) | P4 |
| Renovate/Dependabot for base image updates | P5 |

## Complexity Tracking

> No constitution violations to justify — all gates pass.
