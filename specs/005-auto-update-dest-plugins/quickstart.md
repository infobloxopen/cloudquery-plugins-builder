# Quickstart: Build All Destination Plugins

**Feature**: 005-auto-update-dest-plugins

## Prerequisites

- Docker with Buildx
- `yq` v4+ (`brew install yq` or `sudo snap install yq`)
- `jq` (`brew install jq` or `sudo apt-get install jq`)
- `git`

## 1. Adding a New Destination Plugin

Add an entry to `plugins.yaml`:

```yaml
  - name: kafka
    kind: destination
    version: v5.7.1
    upstream:
      repo: https://github.com/infobloxopen/cloudquery
      tag: plugins-destination-kafka-v5.7.1
      commit: <40-char-sha>  # Resolve with: git ls-remote https://github.com/infobloxopen/cloudquery plugins-destination-kafka-v5.7.1
    build:
      plugin_dir: plugins/destination/kafka
      go_version: "1.25.6"
      ldflags_version_path: >-
        github.com/cloudquery/cloudquery/plugins/destination/kafka/v5/resources/plugin.Version
```

Validate:
```bash
make validate
```

Build:
```bash
make build PLUGIN=kafka
```

## 2. Adding a CGO Plugin (Exception Basis)

For plugins requiring CGO (sqlite, duckdb), add `cgo_required: true`:

```yaml
  - name: sqlite
    kind: destination
    version: v2.14.1
    upstream:
      repo: https://github.com/infobloxopen/cloudquery
      tag: plugins-destination-sqlite-v2.14.1
      commit: <40-char-sha>
    build:
      plugin_dir: plugins/destination/sqlite
      go_version: "1.25.6"
      ldflags_version_path: >-
        github.com/cloudquery/cloudquery/plugins/destination/sqlite/v2/resources/plugin.Version
      cgo_required: true    # Enables CGO build with cc-debian12 base
```

This is strictly **exception-basis**. Only 2 plugins (sqlite, duckdb) require CGO. When `cgo_required: true` is set:
- Build uses `CGO_ENABLED=1`
- Final image uses `gcr.io/distroless/cc-debian12:nonroot` (includes glibc + libstdc++)

## 3. Excluding a Plugin from Publishing

For development/test plugins that should be built but not pushed to GHCR:

```yaml
  - name: test
    kind: destination
    version: v2.8.30
    upstream: { ... }
    build: { ... }
    publish: false
```

## 4. Checking for Plugin Updates

### Dry-Run (see what's available)

```bash
./scripts/update-plugins.sh --dry-run
```

Output:
```text
Plugin              Current     Available   Status
────────────────    ─────────   ─────────   ──────
postgresql          v8.14.1     v8.15.0     UPDATE AVAILABLE
kafka               v5.7.1      v5.7.1      up to date
```

### Apply Updates Locally

```bash
./scripts/update-plugins.sh
make validate
git diff plugins.yaml  # Review changes
```

### Automated Daily Updates (CI)

The `.github/workflows/update-plugins.yaml` workflow:
1. Runs daily at 06:00 UTC
2. Checks all plugins for new versions
3. Opens a PR if updates are found
4. PR triggers full CI validation
5. Auto-merges after checks pass

## 5. Checking for Go Version Updates

### Dry-Run

```bash
./scripts/update-go-version.sh --dry-run
```

### CI Automation

The `.github/workflows/update-go-version.yaml` workflow:
1. Runs weekly on Monday at 09:00 UTC (main-only)
2. Checks for stable Go releases ≥2 weeks old
3. Opens a PR if a newer version is available
4. PR triggers full CI validation

## 6. Understanding Image Tags

Images are tagged with the upstream plugin version plus a git suffix from this repo:

```text
ghcr.io/infobloxopen/cq-destination-postgresql:v8.14.1-g1a2b3c4
                                                 │         │
                                                 │         └── this repo's git ref
                                                 └── upstream plugin version
```

The git suffix ensures that rebuilds of the same upstream version (e.g., after a Dockerfile change) produce distinct, traceable tags.

## 7. Building All Plugins

```bash
make build-all
```

This builds all plugins in `plugins.yaml` sequentially. For parallel builds in CI, use the matrix:

```bash
make matrix  # Outputs JSON for GitHub Actions matrix
```

## 8. Resolving a Commit SHA for a Tag

When adding a new plugin, you need the commit SHA for the tag:

```bash
git ls-remote https://github.com/infobloxopen/cloudquery plugins-destination-kafka-v5.7.1
# Output: <40-char-sha>    refs/tags/plugins-destination-kafka-v5.7.1
```

## 9. Troubleshooting

### Plugin fails to build with CGO_ENABLED=0

If a new plugin fails to build, it likely needs CGO. Check its `go.mod` for:
- `mattn/go-sqlite3` → needs CGO
- `duckdb/duckdb-go` → needs CGO
- `#cgo` directives in imported packages

Add `cgo_required: true` to the plugin's build config.

### `make validate` fails after update

The update script detects this and aborts the commit. Check:
1. Tag exists: `git ls-remote https://github.com/infobloxopen/cloudquery <tag>`
2. Commit SHA matches: compare the SHA from `git ls-remote`
3. Plugin directory exists at that tag

### Smoke test fails

The plugin gRPC server must be listening on port 7777 within 30 seconds. If it fails:
1. Check build logs for error messages
2. Run manually: `docker run --rm -p 7777:7777 <image>`
3. Verify the entrypoint wrapper starts correctly
