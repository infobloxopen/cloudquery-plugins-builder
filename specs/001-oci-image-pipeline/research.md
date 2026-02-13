# Research: OCI Image Pipeline for CloudQuery Plugins

**Feature**: 001-oci-image-pipeline
**Date**: 2026-02-12
**Source Repository**: [`cloudquery/cloudquery`](https://github.com/cloudquery/cloudquery) (GitHub)
**Purpose**: Resolve all NEEDS CLARIFICATION items and inform design decisions.

---

## 1. Tag Naming Convention

CloudQuery uses a **monorepo-scoped tag** convention. Each plugin has its own tag namespace in the form:

```
plugins-destination-<name>-v<major>.<minor>.<patch>
```

**Exact tags for the three target plugins:**

| Plugin | Version | Git Tag |
|--------|---------|---------|
| S3 | v7.10.2 | `plugins-destination-s3-v7.10.2` |
| File | v5.5.1 | `plugins-destination-file-v5.5.1` |
| PostgreSQL | v8.14.1 | `plugins-destination-postgresql-v8.14.1` |

**Evidence**: CHANGELOG.md compare links use this exact format, e.g.:
```
## [7.10.2](https://github.com/cloudquery/cloudquery/compare/plugins-destination-s3-v7.10.1...plugins-destination-s3-v7.10.2)
```

**Implication for pipeline**: When cloning/checking out the upstream source, the pipeline must use the full monorepo tag (e.g., `plugins-destination-s3-v7.10.2`), **not** a bare `v7.10.2` tag.

---

## 2. Repository Layout

The `cloudquery/cloudquery` repository is a **Go monorepo**. Destination plugins live under:

```
plugins/destination/<name>/
```

Relevant directory structure for each target plugin:

```
plugins/destination/s3/
├── main.go                          # Entry point
├── main_fips.go                     # (if exists) FIPS-enabled variant
├── Makefile                         # test, lint, gen targets
├── CHANGELOG.md
├── CONTRIBUTING.md
├── go.mod                           # Independent Go module
├── go.sum
├── coverage.md
├── client/
│   ├── client.go
│   └── spec/
│       ├── spec.go
│       ├── schema.json
│       └── gen/main.go
├── resources/
│   └── plugin/
│       └── plugin.go                # Name, Kind, Team, Version vars
└── docs/
    ├── overview.md
    └── _licenses.md

plugins/destination/file/             # Same structure as s3
plugins/destination/postgresql/       # Same structure, plus main_fips.go
```

Other destination plugins in the monorepo include: bigquery, clickhouse, duckdb, elasticsearch, firehose, gcs, gremlin, kafka, meilisearch, mongodb, mssql, mysql, neo4j, snowflake, sqlite, test.

**Implication for pipeline**: After checking out the monorepo at a tag, the build context is rooted at `plugins/destination/<name>/`. The `go.mod` references sibling packages (e.g., `filetypes`, `codegen`) within the same monorepo.

---

## 3. Go Module Structure

Each destination plugin has its **own independent `go.mod`** file. They are not part of a single workspace module.

### Module paths (including major version suffix per Go convention):

| Plugin | Module Path | Go Version |
|--------|-------------|------------|
| S3 v7.10.2 | `github.com/cloudquery/cloudquery/plugins/destination/s3/v7` | `go 1.25.6` |
| File v5.5.1 | `github.com/cloudquery/cloudquery/plugins/destination/file/v5` | `go 1.25.6` |
| PostgreSQL v8.14.1 | `github.com/cloudquery/cloudquery/plugins/destination/postgresql/v8` | `go 1.25.6` |

### Key shared dependencies (at these versions):

| Dependency | Version |
|-----------|---------|
| `github.com/cloudquery/plugin-sdk/v4` | v4.94.2 |
| `github.com/cloudquery/plugin-pb-go` | v1.27.6 |
| `github.com/apache/arrow-go/v18` | v18.5.1 |
| `github.com/cloudquery/codegen` | v0.3.36 |
| `github.com/cloudquery/filetypes/v4` | v4.6.13 (s3, file only) |

### go.mod replace directive:
All three plugins use the same replace directive:
```
replace github.com/invopop/jsonschema => github.com/cloudquery/jsonschema v0.0.0-20240220124159-92878faa2a66
```

**Implication for pipeline**: The Go version is `1.25.6` — the Dockerfile must pin this exact version. The replace directive means a standard `go build` from within the plugin directory will work correctly. Each plugin is a self-contained module; no workspace-level go.work file is needed.

---

## 4. Plugin Serve Command (gRPC Server Mode)

### Code pattern

Every Go destination plugin follows the same pattern in `main.go`:

```go
import (
    "github.com/cloudquery/plugin-sdk/v4/plugin"
    "github.com/cloudquery/plugin-sdk/v4/serve"
)

func main() {
    p := plugin.NewPlugin(
        internalPlugin.Name,        // e.g., "s3"
        internalPlugin.Version,     // "development" in source, overridden by goreleaser at build time
        client.New,
        plugin.WithKind(internalPlugin.Kind),          // "destination"
        plugin.WithTeam(internalPlugin.Team),           // "cloudquery"
        plugin.WithJSONSchema(spec.JSONSchema),
        plugin.WithConnectionTester(client.NewConnectionTester(client.New)),
    )
    if err := serve.Plugin(p,
        serve.WithPluginSentryDSN(sentryDSN),
        serve.WithDestinationV0V1Server(),
    ).Serve(context.Background()); err != nil {
        log.Fatalf("failed to serve plugin: %v", err)
    }
}
```

### CLI subcommand

Plugins are started with the `serve` subcommand:
```bash
go run main.go serve
```

### Default listen address

From the development documentation and Dockerfiles in the repo:
- Default gRPC address: `localhost:7777`
- For containers, the Dockerfiles use: `serve --address [::]:7777 --log-format json --log-level info`

### Available CLI flags (from Dockerfiles and docs):

| Flag | Purpose | Default |
|------|---------|---------|
| `--address` | gRPC listen address | `localhost:7777` |
| `--log-format` | Log output format (`json`, `text`) | `text` |
| `--log-level` | Log verbosity (`trace`, `debug`, `info`, `warn`, `error`) | `info` |

### Version embedding

The `resources/plugin/plugin.go` file in each plugin contains:
```go
var (
    Name    = "postgresql"    // plugin name
    Kind    = "destination"
    Team    = "cloudquery"
    Version = "development"   // overridden at build time by GoReleaser via -ldflags
)
```

The comment in the source says: *"Don't move this file to a different package, it's used by Go releaser to embed the version in the binary."*

**Implication for pipeline**: The Dockerfile CMD should be:
```dockerfile
CMD ["serve", "--address", "[::]:7777", "--log-format", "json", "--log-level", "info"]
```
The `Version` variable should be set at build time via `-ldflags`:
```
-ldflags "-X github.com/cloudquery/cloudquery/plugins/destination/<name>/v<major>/resources/plugin.Version=v<version>"
```

---

## 5. Build Process and CGO Dependencies

### Target plugins: All pure Go (no CGO)

| Plugin | CGO Required | Evidence |
|--------|-------------|----------|
| **S3** | ❌ No | No `plugin.WithBuildTargets` with `CGO: true`; no build tags |
| **File** | ❌ No | No `plugin.WithBuildTargets` with `CGO: true`; no build tags |
| **PostgreSQL** | ❌ No | Uses `pgx` driver (pure Go); no CGO build targets. Has `//go:build !fipsEnabled` tag (only for FIPS variant separation) |

### Contrast with CGO-requiring plugins:

| Plugin | CGO Required | Evidence |
|--------|-------------|----------|
| SQLite | ✅ Yes | `plugin.WithBuildTargets([]plugin.BuildTarget{{..., CGO: true}, ...})` + custom `gencc.sh`/`gencpp.sh` cross-compile scripts |
| DuckDB | ✅ Yes | Same CGO build targets pattern + custom CC/CPP scripts |

### Build command

From the Makefile and scaffold templates, a plugin binary is built with:
```bash
cd plugins/destination/<name>
go build -o <binary-name> .
```

Or with version embedding:
```bash
go build -ldflags "-X .../resources/plugin.Version=v8.14.1" -o plugin .
```

### CGO_ENABLED setting

For s3, file, and postgresql: `CGO_ENABLED=0` is safe and recommended for static binaries in containers.

### PostgreSQL FIPS variant

The postgresql plugin has two entry points:
- `main.go` — `//go:build !fipsEnabled` (default, non-FIPS)
- `main_fips.go` — `//go:build fipsEnabled` (FIPS mode using `crypto/fips140`)

For our pipeline, we use the default (non-FIPS) build.

**Implication for pipeline**: The Dockerfile can use a simple multi-stage build:
```dockerfile
FROM golang:1.25.6 AS builder
# ... copy source, go build with CGO_ENABLED=0 ...

FROM gcr.io/distroless/static-debian12:nonroot
# ... copy binary, set CMD ...
```

No need for GCC, CGO toolchains, or cross-compilation scripts for these three plugins.

---

## 6. License

The `cloudquery/cloudquery` repository is licensed under the **Mozilla Public License, Version 2.0 (MPL-2.0)**.

The root `LICENSE` file begins with:
```
Mozilla Public License, version 2.0
```

Individual plugins (e.g., `plugins/source/airtable/LICENSE`) also use MPL-2.0.

The core SDK (`plugin-sdk/v4`) is also MPL-2.0.

### MPL-2.0 implications for our pipeline:

- **Permissive for our use case**: MPL-2.0 allows building and distributing binaries from the source. Modified source files must remain under MPL-2.0, but our pipeline does not modify the source — it builds unmodified upstream code into OCI images.
- **File-level copyleft**: If we modify any MPL-2.0 source file, that file must remain under MPL-2.0. Since we build upstream source as-is, this is not a concern.
- **No "infectious" copyleft**: Unlike GPL, MPL-2.0 does not require our Dockerfile, CI workflow, or other pipeline code to be MPL-2.0 licensed.
- **Attribution**: The OCI image should include upstream license information. The built binary already embeds license data via `gen-licenses` Makefile target.

---

## Summary Table

| Aspect | Finding |
|--------|---------|
| **Tag format** | `plugins-destination-<name>-v<version>` |
| **Plugin source path** | `plugins/destination/<name>/` |
| **Go module** | Independent `go.mod` per plugin, module path includes major version |
| **Go version** | `1.25.6` (all three plugins) |
| **Core SDK** | `github.com/cloudquery/plugin-sdk/v4` v4.94.2 |
| **Serve command** | `./binary serve --address [::]:7777 --log-format json --log-level info` |
| **Default port** | 7777 (gRPC) |
| **CGO required** | No (s3, file, postgresql are all pure Go) |
| **Version ldflags** | `-X .../resources/plugin.Version=v<version>` |
| **License** | MPL-2.0 |
| **FIPS variant** | PostgreSQL has `main_fips.go` (not needed for our pipeline) |

---

## Design Decisions (consolidated)

| ID | Decision | Rationale | Alternatives Rejected |
|----|----------|-----------|----------------------|
| D1 | Build from monorepo tag (`plugins-destination-<name>-v<version>`) | Immutable reference; pins all in-repo deps | Sparse checkout (fragile), release binaries (redistribution risk) |
| D2 | Entrypoint: `serve --address [::]:7777 --log-format json --log-level info` | Default binds loopback only; `[::]` needed for k8s pod networking | Leave default localhost (breaks k8s), unix sockets (breaks k8s Service) |
| D3 | `CGO_ENABLED=0` static binary + distroless final image | All 3 plugins are pure Go; distroless minimizes CVE surface | Alpine (unnecessary libc), scratch (no CA certs/tzdata) |
| D4 | Docker Buildx + QEMU for multi-arch | Standard GHA approach; handles OCI manifest list + attestations | Native arm64 runners (cost), manual `docker manifest create` (complex) |
| D5 | Image name: `ghcr.io/<org>/cloudquery-plugin-<name>:<version>` | Clear namespace, 1:1 version mapping, no `latest` tag | Abbreviated names (unclear), kind-in-name (verbose for MVP) |
| D6 | Go entrypoint wrapper for env var override | SDK lacks env var support; Constitution requires it; keeps distroless | Shell script (needs shell in image), require CLI args only (violates constitution) |
| D7 | Buildx `--sbom=true --provenance=mode=max` + cosign keyless | Native Buildx integration; OIDC = no secrets to manage | Separate syft step (extra complexity), long-lived keys (prohibited) |
| D8 | TCP port check smoke test (30s timeout) | Simplest reliable check that plugin listens | gRPC health check (needs client), crash-only check (insufficient) |

````
