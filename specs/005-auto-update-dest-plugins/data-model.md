# Data Model: Build All Destination Plugins with Automated Daily Updates

**Feature**: 005-auto-update-dest-plugins
**Date**: 2026-02-22

## Entities

### 1. Plugin Manifest Entry (`plugins.yaml`) — Extended

The existing manifest schema (from feature 001) is extended with optional fields for CGO support and publish control.

```yaml
apiVersion: v1
plugins:
  - name: postgresql                        # Plugin short name
    kind: destination                       # "source" or "destination"
    version: v8.14.1                        # Upstream plugin semver
    upstream:
      repo: https://github.com/infobloxopen/cloudquery
      tag: plugins-destination-postgresql-v8.14.1
      commit: a5431aea2c8920890ea94de5abe7a485bd29e2f6
    build:
      plugin_dir: plugins/destination/postgresql
      go_version: "1.25.6"
      ldflags_version_path: >-
        github.com/cloudquery/cloudquery/plugins/destination/postgresql/v8/resources/plugin.Version
      cgo_required: false                   # NEW: opt-in CGO support (default: false)
    publish: true                           # NEW: whether to push image to GHCR (default: true)

  - name: sqlite
    kind: destination
    version: v2.14.1
    upstream:
      repo: https://github.com/infobloxopen/cloudquery
      tag: plugins-destination-sqlite-v2.14.1
      commit: <sha>
    build:
      plugin_dir: plugins/destination/sqlite
      go_version: "1.25.6"
      ldflags_version_path: >-
        github.com/cloudquery/cloudquery/plugins/destination/sqlite/v2/resources/plugin.Version
      cgo_required: true                    # CGO exception — uses mattn/go-sqlite3
    publish: true

  - name: test
    kind: destination
    version: v2.8.30
    upstream:
      repo: https://github.com/infobloxopen/cloudquery
      tag: plugins-destination-test-v2.8.30
      commit: <sha>
    build:
      plugin_dir: plugins/destination/test
      go_version: "1.25.6"
      ldflags_version_path: >-
        github.com/cloudquery/cloudquery/plugins/destination/test/v2/resources/plugin.Version
    publish: false                          # Development utility — do not publish
```

### New Fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `build.cgo_required` | boolean | No | `false` | When `true`, the build uses `CGO_ENABLED=1` and a distroless base with libc/libstdc++ (`cc-debian12`) instead of the fully static base. Exception-basis only. |
| `publish` | boolean | No | `true` | When `false`, the image is built but not pushed to GHCR. Used for development/test plugins. |

### Validation Rules (additions)

- `cgo_required` must be a boolean if present
- `publish` must be a boolean if present
- If `cgo_required` is `true` and `publish` is `true`, the plugin is built with CGO and published

### CGO Plugins (as of this specification)

Only 2 plugins require CGO:

| Plugin | CGO Dependency | Reason |
|--------|---------------|--------|
| sqlite | `mattn/go-sqlite3` | C wrapper for SQLite library |
| duckdb | `duckdb/duckdb-go/v2` | C++ DuckDB bindings |

All other plugins (18) build fully static with `CGO_ENABLED=0`.

---

### 2. OCI Image Tag Format

```text
Format:  ghcr.io/infobloxopen/cq-<kind>-<name>:<upstream-version>-<git-suffix>

Examples:
  ghcr.io/infobloxopen/cq-destination-postgresql:v8.14.1-g1a2b3c4
  ghcr.io/infobloxopen/cq-destination-sqlite:v2.14.1-g1a2b3c4
  ghcr.io/infobloxopen/cq-destination-s3:v7.10.2-gv0.5.0

Components:
  cq-              Prefix: image originates from upstream CloudQuery source
  <kind>           "destination" (future: "source")
  <name>           Plugin short name from manifest
  <upstream-version>  Plugin version from manifest (e.g., v8.14.1)
  <git-suffix>     git describe --always from this repository
```

The git suffix provides traceability: the same upstream plugin version can be rebuilt with Dockerfile or entrypoint changes, and the git suffix distinguishes the builds.

---

### 3. Dockerfile Build Args — Extended

| Build Arg | Source | Default | Description |
|-----------|--------|---------|-------------|
| `GO_VERSION` | `build.go_version` | `1.25.6` | Go toolchain version |
| `PLUGIN_DIR` | `build.plugin_dir` | `plugins/destination/postgresql` | Plugin source directory |
| `PLUGIN_VERSION` | `version` | `v8.14.1` | Upstream plugin version |
| `LDFLAGS_VERSION_PATH` | `build.ldflags_version_path` | `""` | Go ldflags -X path |
| `BIN_NAME` | `build.bin_name` | `plugin` | Output binary name |
| `UPSTREAM_REPO` | `upstream.repo` | `https://github.com/infobloxopen/cloudquery` | Upstream repository |
| `UPSTREAM_TAG` | `upstream.tag` | `plugins-destination-postgresql-v8.14.1` | Git tag to clone |
| `CGO_ENABLED` | Derived from `build.cgo_required` | `0` | **NEW**: `0` or `1` |
| `BASE_IMAGE` | Derived from `build.cgo_required` | `gcr.io/distroless/static-debian12:nonroot` | **NEW**: Final stage base |

When `cgo_required: true`:
- `CGO_ENABLED=1`
- `BASE_IMAGE=gcr.io/distroless/cc-debian12:nonroot`

---

### 4. Update Script Output

The update script produces two types of output:

#### Update Report (stdout / CI log)

```text
[INFO]  Checking 20 plugins for updates...
[INFO]  postgresql: v8.14.1 → v8.15.0 (tag: plugins-destination-postgresql-v8.15.0)
[INFO]  kafka: v5.7.1 → v5.8.0 (tag: plugins-destination-kafka-v5.8.0)
[INFO]  s3: v7.10.2 — up to date
[INFO]  ...
[INFO]  2 plugins updated, 18 up to date
[WARN]  New plugins detected (not in manifest): redshift
```

#### Dry-Run Report

```text
Plugin              Current     Available   Status
────────────────    ─────────   ─────────   ──────
postgresql          v8.14.1     v8.15.0     UPDATE AVAILABLE
kafka               v5.7.1      v5.8.0      UPDATE AVAILABLE
s3                  v7.10.2     v7.10.2     up to date
file                v5.5.1      v5.5.1      up to date
...
```

#### Commit Message Format

```text
chore: update plugin versions

Updated plugins:
  - postgresql: v8.14.1 → v8.15.0
  - kafka: v5.7.1 → v5.8.0

Signed-off-by: github-actions[bot] <github-actions[bot]@users.noreply.github.com>
```

---

### 5. Go Version Update Output

```text
[INFO]  Current Go version in manifest: 1.25.6
[INFO]  Latest stable Go release ≥2 weeks old: go1.26.0 (released 2026-02-08)
[INFO]  Updating all plugins from go_version 1.25.6 → 1.26.0
```

---

### 6. Complete Plugin Inventory

| # | Plugin | Version | CGO | Publish | Notes |
|---|--------|---------|-----|---------|-------|
| 1 | azblob | v4.5.2 | No | Yes | Azure Blob Storage |
| 2 | bigquery | v4.7.2 | No | Yes | Google BigQuery |
| 3 | clickhouse | v8.1.1 | No | Yes | ClickHouse |
| 4 | csv | v1.2.2 | No | Yes | CSV files |
| 5 | duckdb | v6.3.1 | **Yes** | Yes | DuckDB (CGO: duckdb-go) |
| 6 | elasticsearch | v3.6.1 | No | Yes | Elasticsearch |
| 7 | file | v5.5.1 | No | Yes | Local filesystem |
| 8 | firehose | v2.8.2 | No | Yes | AWS Firehose |
| 9 | gcs | v5.5.2 | No | Yes | Google Cloud Storage |
| 10 | gremlin | v2.7.2 | No | Yes | Apache TinkerPop/Gremlin |
| 11 | kafka | v5.7.1 | No | Yes | Apache Kafka |
| 12 | meilisearch | v2.6.1 | No | Yes | Meilisearch |
| 13 | mongodb | v2.8.2 | No | Yes | MongoDB |
| 14 | mssql | v5.3.2 | No | Yes | Microsoft SQL Server |
| 15 | mysql | v5.6.1 | No | Yes | MySQL |
| 16 | neo4j | v5.5.1 | No | Yes | Neo4j |
| 17 | postgresql | v8.14.1 | No | Yes | PostgreSQL |
| 18 | s3 | v7.10.2 | No | Yes | AWS S3 |
| 19 | snowflake | v5.2.1 | No | Yes | Snowflake (pure Go) |
| 20 | sqlite | v2.14.1 | **Yes** | Yes | SQLite (CGO: go-sqlite3) |
| 21 | test | v2.8.30 | No | **No** | Dev/test utility |

**Total**: 21 plugins (20 publishable, 2 CGO, 1 non-publishable)

---

## State Transitions

### Plugin Version Lifecycle

```text
                    ┌────────────────┐
                    │  Not in fork   │  (no tags exist)
                    └───────┬────────┘
                            │  first tag appears
                            ▼
                    ┌────────────────┐
                    │  Detected      │  (new plugin notice in CI log)
                    └───────┬────────┘
                            │  human adds to manifest
                            ▼
                    ┌────────────────┐
                    │  In Manifest   │  (defined in plugins.yaml)
                    │  (current)     │
                    └───────┬────────┘
                            │  newer tag detected by update script
                            ▼
                    ┌────────────────┐
                    │  Update        │  (PR opened with new version)
                    │  Pending       │
                    └───────┬────────┘
                            │  PR merged (CI passes)
                            ▼
                    ┌────────────────┐
                    │  In Manifest   │  (updated version)
                    │  (current)     │
                    └────────────────┘
```

### Build Decision Tree

```text
For each plugin in plugins.yaml:

  1. Is publish == false?
     → Build only (no push to GHCR)

  2. Is cgo_required == true?
     → CGO_ENABLED=1, BASE_IMAGE=cc-debian12:nonroot

  3. Default:
     → CGO_ENABLED=0, BASE_IMAGE=static-debian12:nonroot

  4. Tag = <version>-<git-suffix>
```

## Relationships

```text
plugins.yaml ──(1:N)──► Plugin Entry ──(1:1)──► OCI Image
                              │
                              ├── upstream.tag ──► git tag in fork
                              ├── upstream.commit ──► commit SHA in fork
                              └── build.cgo_required ──► CGO_ENABLED + BASE_IMAGE
```
