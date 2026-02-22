# Research: Build All Destination Plugins with Automated Daily Updates

**Feature**: 005-auto-update-dest-plugins
**Date**: 2026-02-22

## R1: CGO Requirements per Plugin

### Decision

Only **2 out of 20+** Go destination plugins require CGO: **sqlite** and **duckdb**. All others (including snowflake) are pure Go and build with `CGO_ENABLED=0`.

### Findings

| Plugin | CGO Required | Key Dependency | Distroless Base | Notes |
|--------|-------------|----------------|-----------------|-------|
| **sqlite** | Yes | `mattn/go-sqlite3` | `cc-debian12:nonroot` | C library wrapping SQLite; dynamically linked to glibc |
| **duckdb** | Yes | `duckdb/duckdb-go/v2` | `cc-debian12:nonroot` | C++ library; needs libstdc++ |
| **snowflake** | No | `snowflakedb/gosnowflake` | `static-debian12:nonroot` | Pure Go driver, no CGO |
| **motherduck** | N/A | — | — | **Does not exist as a separate plugin** in the fork. MotherDuck is accessed via the duckdb plugin with a `motherduck:` connection string |

### Rationale

- `mattn/go-sqlite3` compiles the C SQLite library at build time via `#cgo` directives. Cannot build with `CGO_ENABLED=0`.
- `duckdb/duckdb-go/v2` ships pre-built static `.a` libraries per platform but still requires CGO linking. DuckDB is C++, so the runtime image needs both glibc and libstdc++.
- `snowflakedb/gosnowflake` is pure Go using `database/sql` — no C bindings.

### Alternatives Considered

- **Use `gcr.io/distroless/base-debian12:nonroot`** (glibc only, no libstdc++) — rejected because duckdb needs libstdc++.
- **Use separate base images per CGO plugin** (base for sqlite, cc for duckdb) — rejected; unnecessary complexity. `cc-debian12` is a superset of `base-debian12` and works for both.
- **Use Alpine musl-based images** — rejected; DuckDB's pre-built bindings are compiled against glibc, not musl.

### Unified CGO Base Image

**`gcr.io/distroless/cc-debian12:nonroot`** for ALL CGO plugins. It includes glibc + libstdc++, which is a superset of what any CGO plugin needs. Simplifies the Dockerfile to a two-option choice:

| `build.cgo_required` | `CGO_ENABLED` | Base Image |
|-----------------------|---------------|------------|
| `false` (default) | `0` | `gcr.io/distroless/static-debian12:nonroot` |
| `true` | `1` | `gcr.io/distroless/cc-debian12:nonroot` |

### CGO Cross-Compilation Consideration

CGO cross-compilation (e.g., building `linux/arm64` on an `amd64` host) requires a cross-compiler (`aarch64-linux-gnu-gcc`, `aarch64-linux-gnu-g++`). The standard `golang:` Docker image does not include cross-compilers. Options:

1. **Install cross-compilers in the Dockerfile** — adds build complexity
2. **Build with QEMU emulation** — slower but works without cross-compilers (current buildx approach uses QEMU)
3. **Build only `linux/amd64` for CGO plugins** — acceptable trade-off for the 2 CGO plugins

Recommendation: Start with QEMU emulation (already available via buildx), accept slower builds for 2 plugins. If build times are unacceptable, add cross-compilers as a follow-up.

### Motherduck Resolution

The `motherduck` plugin does not exist as a separate directory in the Infoblox fork or upstream CloudQuery. MotherDuck is a cloud-hosted DuckDB service accessed through the duckdb plugin's connection string. **Remove motherduck from the plugin inventory.**

---

## R2: Go Version API and Update Strategy

### Decision

Use the Go downloads API (`go.dev/dl/?mode=json`) to list stable versions, then query the GitHub API (`golang/go` tags) to determine release dates. Pick the newest stable version that is ≥14 days old.

### Findings

**Go Downloads API** (`https://go.dev/dl/?mode=json`):
- Returns JSON array of stable releases, ordered newest first
- Each entry has `version` (e.g., `"go1.26.0"`), `stable` (bool), and `files` (array)
- **Does NOT include a release date**
- Only returns currently-maintained releases (2 minor series at a time)

**Release Date Discovery** via GitHub API:
1. `GET https://api.github.com/repos/golang/go/git/ref/tags/go1.23.1` → commit SHA
2. `GET https://api.github.com/repos/golang/go/git/commits/{sha}` → `committer.date`
- Rate limit: 60 req/hr unauthenticated, 5000/hr with `GITHUB_TOKEN`
- Only need 2-4 API calls per run (one per maintained version)

**Semver Parsing**: `go1.23.1` → strip `go` prefix → `1.23.1`
```bash
semver="${version#go}"
```

**Version Comparison**: Use `sort -V` (GNU coreutils, available on Ubuntu runners)
```bash
newer=$(printf '%s\n%s' "$ver1" "$ver2" | sort -V | tail -n1)
```

### Algorithm

```
1. Fetch stable versions from go.dev/dl/?mode=json
2. CUTOFF = today - 14 days
3. For each version (newest first):
     Get release date from GitHub API
     If release_date ≤ CUTOFF → candidate = version; break
4. If no candidate → no update, exit
5. If candidate > current go_version in plugins.yaml → update all entries
6. Commit via PR
```

### Edge Cases

| Edge Case | Handling |
|-----------|----------|
| Two maintained minor versions (e.g., 1.25.x and 1.26.x) | Pick newest version that is ≥2 weeks old. If 1.26.0 is too new, fall back to latest 1.25.x patch |
| Brand-new major release | Won't be ≥2 weeks old yet; falls back to previous series. Desired behavior — stabilization buffer |
| RC/beta versions | API only returns `stable: true`; no filtering needed |
| GitHub API rate limiting | Use `GITHUB_TOKEN` in CI; only 2-4 calls per run |
| `sort -V` on macOS | CI runs on Ubuntu; not an issue. Document for local use: `brew install coreutils && gsort -V` |

### Alternatives Considered

- **Scrape `go.dev/doc/devel/release`** — rejected; HTML parsing is fragile
- **Hardcode release schedule (every 6 months + patches)** — rejected; unreliable
- **Use only the downloads API (no date check)** — rejected; can't enforce the 2-week stabilization buffer

---

## R3: Auto-Commit Strategy for CI

### Decision

Create a Pull Request using `peter-evans/create-pull-request` authenticated with a GitHub App token via `actions/create-github-app-token`. This is the only approach compatible with branch protection requirements.

### Rationale

The constitution states:
- "direct pushes to `main` are prohibited"
- "pull-request checks MUST be required (branch protection)"

This eliminates direct push approaches. The `GITHUB_TOKEN` approach fails because events from `GITHUB_TOKEN` do **not** trigger subsequent workflows (GitHub prevents recursive loops), meaning the PR's required status checks would never run.

### Approach Comparison

| Approach | Branch Protection | Triggers CI | Security | Recommended |
|----------|------------------|-------------|----------|-------------|
| `GITHUB_TOKEN` direct push | Blocked | N/A | Best | No |
| `GITHUB_TOKEN` + PR | Compatible | **No** (fatal) | Best | No |
| PAT + PR | Compatible | Yes | Worst | No |
| **GitHub App + PR** | **Compatible** | **Yes** | **Good** | **Yes** |

### Implementation

**Actions:**
- `actions/create-github-app-token` (official first-party) — generates short-lived app token
- `peter-evans/create-pull-request` — creates branch, commits, opens PR

**GitHub App Permissions:**
- `contents: write` — push branches, commit files
- `pull-requests: write` — create and update PRs

**Repo Secrets:**
- `APP_ID` — GitHub App numeric ID
- `APP_PRIVATE_KEY` — App PEM private key

**Key Behaviors:**
- If no files changed → `peter-evans/create-pull-request` skips PR creation (clean exit)
- If PR already exists for the branch → updates existing PR
- `delete-branch: true` → cleans up branch after merge
- App token in checkout ensures pushed branch triggers `pr-validate.yaml`
- Optional: `gh pr merge --auto --squash` for fully automated merge after CI passes

### Alternatives Considered

- **Personal Access Token** — rejected; tied to personal account, long-lived, organizational risk
- **Direct push with `GITHUB_TOKEN`** — rejected; violates constitution (branch protection)
- **PR with `GITHUB_TOKEN`** — rejected; won't trigger CI checks, PR can never merge

---

## R4: Plugin ldflags_version_path Pattern

### Decision

All Go-based destination plugins follow a consistent pattern for version injection:
```
github.com/cloudquery/cloudquery/plugins/destination/<name>/v<major>/resources/plugin.Version
```

### Rationale

Verified across existing plugins (s3, file, postgresql). The pattern uses the Go module path, which includes the major version. When a major version bump occurs, the `v<major>` segment must be updated.

### Update Script Implication

When the update script detects a major version bump (e.g., v7.x → v8.x), it must update the `ldflags_version_path` by replacing the `v<old-major>` with `v<new-major>` in the path.

---

## R5: Git Suffix for Image Tags

### Decision

Use `git describe --always` from this repository to generate a short commit hash suffix. Format: `g<short-sha>` (e.g., `g1a2b3c4`).

### Rationale

- `git describe --tags --always` falls back to the short commit SHA if no annotated tag is present
- The `g` prefix distinguishes the git ref from the upstream version number
- The suffix traces the image to the exact build of this repo, not just the upstream plugin version
- Multiple builds of the same upstream version (e.g., due to Dockerfile changes) produce distinct tags

### Tag Format

```
<upstream-version>-<git-suffix>
```

Examples:
- `v8.14.1-g1a2b3c4` — built from commit 1a2b3c4 of this repo
- `v8.14.1-v0.5.0-3-g1a2b3c4` — built from 3 commits after this repo's v0.5.0 tag

For consistency, use `git describe --always --dirty` to also flag uncommitted changes during local builds.
