# CloudQuery Plugins Builder

OCI image pipeline for CloudQuery destination plugins. Reads a declarative `plugins.yaml` manifest, builds multi-architecture OCI images from upstream open-source source code, and publishes them to GHCR with SBOM, provenance, and cosign attestations.

## Purpose

Infoblox needs to deploy CloudQuery destination plugins as standalone gRPC containers in Kubernetes. This repository provides:

- **A single `plugins.yaml` manifest** that pins upstream plugin versions to exact git commits
- **A generic multi-stage Dockerfile** parameterised by build args — one Dockerfile builds any plugin
- **A CI/CD pipeline** (GitHub Actions) that derives its build matrix entirely from the manifest
- **Kubernetes deployment examples** for each plugin
- **Security by default** — distroless base image, non-root user, cosign signing, SBOM/provenance attestations

## Architecture

```
plugins.yaml
    │
    ▼
┌─────────────────────────┐
│  generate-matrix.sh     │  Parse manifest → GitHub Actions matrix
└───────────┬─────────────┘
            │
            ▼  (per plugin)
┌─────────────────────────┐
│  validate-manifest.sh   │  JSON Schema check + upstream tag/commit verification
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  Dockerfile             │  3-stage build:
│  (parameterised)        │    1. Clone upstream → build plugin binary
│                         │    2. Build Go entrypoint wrapper
│                         │    3. Copy both into distroless image
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  smoke-test.sh          │  TCP port check on 7777 (30s timeout)
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  GHCR                   │  Push + cosign sign + SBOM/provenance
└─────────────────────────┘
```

## Quickstart

### Prerequisites

- Docker (with Buildx enabled)
- `yq` (YAML processor)
- `jq` (JSON processor)
- Go 1.25.6+

### Build a single plugin

```bash
make build PLUGIN=postgresql
```

### Run the smoke test

```bash
make smoke-test PLUGIN=postgresql
```

### Build all plugins

```bash
make build-all
```

### Validate the manifest

```bash
make validate
```

For the full getting-started walkthrough, see [specs/001-oci-image-pipeline/quickstart.md](specs/001-oci-image-pipeline/quickstart.md).

## Manifest Reference

The `plugins.yaml` file is the single source of truth for what gets built. It is validated against the JSON Schema at `schemas/plugins-manifest.schema.json`.

```yaml
apiVersion: v1
plugins:
  - name: postgresql              # Plugin short name (used in image tag)
    kind: destination             # "source" or "destination"
    version: v8.14.1              # Semantic version (matches upstream tag)
    upstream:
      repo: https://github.com/infobloxopen/cloudquery
      tag: plugins-destination-postgresql-v8.14.1
      commit: a5431aea2c8920890ea94de5abe7a485bd29e2f6  # Pinned for reproducibility
    build:
      plugin_dir: plugins/destination/postgresql         # Relative path in monorepo
      go_version: "1.25.6"
      ldflags_version_path: >-                           # Optional: inject version at build time
        github.com/cloudquery/cloudquery/plugins/destination/postgresql/v5/resources/plugin.Version
      cgo_required: false                                # Optional: default false
    publish: true                                        # Optional: default true
```

### Plugin Inventory

The manifest currently tracks **21 destination plugins**:

| Plugin | Version | CGO | Publish | Notes |
|--------|---------|-----|---------|-------|
| azblob | v4.5.2 | No | Yes | Azure Blob Storage |
| bigquery | v4.7.2 | No | Yes | Google BigQuery |
| clickhouse | v8.1.1 | No | Yes | ClickHouse |
| csv | v1.2.2 | No | Yes | CSV files |
| duckdb | v6.3.1 | **Yes** | Yes | Embedded OLAP (requires CGO) |
| elasticsearch | v3.6.1 | No | Yes | Elasticsearch |
| file | v5.5.1 | No | Yes | Local file output |
| firehose | v2.8.2 | No | Yes | AWS Firehose |
| gcs | v5.5.2 | No | Yes | Google Cloud Storage |
| gremlin | v2.7.2 | No | Yes | Apache TinkerPop/Gremlin |
| kafka | v5.7.1 | No | Yes | Apache Kafka |
| meilisearch | v2.6.1 | No | Yes | Meilisearch |
| mongodb | v2.8.2 | No | Yes | MongoDB |
| mssql | v5.3.2 | No | Yes | Microsoft SQL Server |
| mysql | v5.6.1 | No | Yes | MySQL |
| neo4j | v5.5.1 | No | Yes | Neo4j graph database |
| postgresql | v8.14.1 | No | Yes | PostgreSQL |
| s3 | v7.10.2 | No | Yes | Amazon S3 |
| snowflake | v5.2.1 | No | Yes | Snowflake |
| sqlite | v2.14.1 | **Yes** | Yes | SQLite (requires CGO) |
| test | v2.8.30 | No | **No** | Test-only plugin (not published) |

### CGO Support

Plugins that depend on C libraries set `cgo_required: true` in their build configuration. This changes:
- **Build**: `CGO_ENABLED=1` is passed to the Go compiler
- **Base image**: Switches from `static-debian12` to `cc-debian12` (includes glibc/libgcc)

Currently only **sqlite** and **duckdb** require CGO. See [ADR 005](docs/adr/005-cgo-exception-basis.md) for details.

### Adding a new plugin

1. Look up the plugin in the [Infoblox CloudQuery fork](https://github.com/infobloxopen/cloudquery) (forked from the [upstream CloudQuery monorepo](https://github.com/cloudquery/cloudquery))
2. Find the latest release tag (e.g., `plugins-destination-mysql-v3.2.0`)
3. Resolve the tag to a commit SHA: `git ls-remote https://github.com/infobloxopen/cloudquery plugins-destination-mysql-v3.2.0`
4. Add an entry to `plugins.yaml`
5. Run `make validate` to verify schema + upstream refs
6. Open a PR — CI will build + smoke test the image

## Image Naming Convention

```
ghcr.io/infobloxopen/cq-<kind>-<name>:<version>-<git-suffix>
```

Where `<kind>` is `source` or `destination`, and `<git-suffix>` is derived from `git describe --always --dirty` for traceability.

Examples:
- `ghcr.io/infobloxopen/cq-destination-postgresql:v8.14.1-abc1234`
- `ghcr.io/infobloxopen/cq-destination-s3:v7.10.2-abc1234`
- `ghcr.io/infobloxopen/cq-destination-duckdb:v6.3.1-abc1234`

See [ADR 004](docs/adr/004-rename-image-convention.md) for the naming convention rationale.

### OCI Labels

Every image includes standard OCI labels:
- `org.opencontainers.image.source` — this repository URL
- `org.opencontainers.image.version` — plugin version
- `org.opencontainers.image.title` — plugin name
- `org.opencontainers.image.description` — description
- `org.opencontainers.image.revision` — upstream commit SHA

## Kubernetes Deployment

Each plugin includes deployment examples in `examples/<plugin>/`:

| File | Purpose |
|------|---------|
| `deployment.yaml` | Kubernetes Deployment + Service (gRPC server on port 7777) |
| `sync-job.yaml` | Kubernetes Job running a CloudQuery sync using the gRPC plugin |
| `cloudquery.yaml` | CloudQuery configuration referencing the gRPC endpoint |

### Deploy the PostgreSQL plugin

```bash
# Deploy as a gRPC server
kubectl apply -f examples/postgresql/deployment.yaml

# Wait for readiness
kubectl wait --for=condition=ready pod -l app=cq-destination-postgresql --timeout=60s

# Run a sync job
kubectl apply -f examples/postgresql/sync-job.yaml
kubectl logs -f job/cloudquery-sync-postgresql
```

### Runtime contract

- **Entrypoint**: `/entrypoint` → execs `/plugin`
- **Default listen address**: `[::]:7777`
- **Environment variables**:
  - `CQ_PLUGIN_ADDRESS` — gRPC bind address (default: `[::]`)
  - `CQ_PLUGIN_PORT` — gRPC port (default: `7777`)
- **User**: non-root (UID 65534)
- **Filesystem**: read-only rootfs supported

## Project Structure

```
├── plugins.yaml                  # Plugin manifest (source of truth)
├── Dockerfile                    # Generic multi-stage Dockerfile
├── Makefile                      # Developer targets
├── schemas/
│   ├── plugins-manifest.schema.json
│   └── build-index.schema.json
├── cmd/entrypoint/main.go        # Go entrypoint wrapper
├── scripts/
│   ├── build.sh                  # Build single plugin
│   ├── build-all.sh              # Build all plugins
│   ├── smoke-test.sh             # TCP smoke test
│   ├── validate-manifest.sh      # Schema + ref validation
│   ├── generate-matrix.sh        # GHA matrix generation
│   ├── generate-build-index.sh   # Build index aggregation
│   ├── update-plugins.sh         # Auto-update plugin versions
│   ├── update-go-version.sh      # Auto-update Go version
│   └── detect-new-plugins.sh     # Detect untracked plugins
├── .github/
│   ├── workflows/
│   │   ├── publish.yaml          # Main branch → GHCR
│   │   ├── pr-validate.yaml      # PR → build + test (no push)
│   │   ├── check-updates.yaml    # Weekly upstream check
│   │   ├── update-plugins.yaml   # Daily plugin version updates
│   │   └── update-go-version.yaml # Weekly Go version updates
│   └── actions/build-plugin/
│       └── action.yaml           # Reusable composite action
├── examples/                     # K8s deployment examples per plugin
├── docs/
│   ├── build-index.md            # Auto-generated build index
│   └── adr/                      # Architecture Decision Records
└── specs/                        # Feature specifications (speckit)
```

## CI Pipelines

### PR Validation (`pr-validate.yaml`)

On every PR that modifies `plugins.yaml`, `Dockerfile`, `scripts/**`, or workflows:

1. Validate manifest against JSON Schema
2. Verify upstream tag + commit SHA for each plugin
3. Build images (no push)
4. Run smoke tests

### Main Branch Publish (`publish.yaml`)

On merge to `main` when `plugins.yaml` changes:

1. Validate manifest
2. Build multi-arch images (amd64 + arm64)
3. Push to GHCR
4. Sign with cosign (keyless OIDC)
5. Generate SBOM + provenance
6. Update `docs/build-index.md`

### Upstream Update Check (`check-updates.yaml`)

Weekly cron — checks for newer plugin versions upstream and opens a PR.

### Plugin Version Updates (`update-plugins.yaml`)

Daily cron at 06:00 UTC — automatically detects new upstream destination plugin releases:

1. Runs `scripts/update-plugins.sh --dry-run` to check for updates
2. Applies updates to `plugins.yaml` (tag, commit SHA, and ldflags path for major bumps)
3. Validates manifest with `make validate`
4. Detects newly published plugins not yet in the manifest
5. Opens a PR on the `auto/update-plugins` branch for human review

Also supports `workflow_dispatch` for on-demand triggering.

### Go Version Updates (`update-go-version.yaml`)

Weekly cron on Mondays at 09:00 UTC — updates the Go toolchain version:

1. Fetches the latest stable Go release that is ≥14 days old (stabilization buffer)
2. Updates `go_version` in `plugins.yaml` if a newer version is available
3. Validates manifest and opens a PR on the `auto/update-go-version` branch

See [ADR 006](docs/adr/006-auto-update-pipeline.md) for the pipeline design rationale.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes (typically editing `plugins.yaml` or improving scripts)
4. Run `make validate` to check manifest integrity
5. Run `make build PLUGIN=<name>` to test locally
6. Open a Pull Request

All PRs require:
- Schema validation pass
- Upstream reference verification
- Successful image build + smoke test

## License

This project is licensed under the Apache License 2.0. See [LICENSE](LICENSE) for the full text.

The OCI images contain software built from upstream CloudQuery plugins, which are licensed under the Mozilla Public License 2.0 (MPL-2.0). Upstream license files are included in the images at `/licenses/`.
