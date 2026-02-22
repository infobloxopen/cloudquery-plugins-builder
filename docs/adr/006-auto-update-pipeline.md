# ADR 006: Automated Update Pipeline

**Date**: 2026-06-15
**Status**: Accepted
**Decision**: D6 — Daily plugin updates and weekly Go updates via GitHub Actions with PR-based workflow

## Context

The plugin manifest (`plugins.yaml`) pins each plugin to a specific upstream tag and commit SHA. As CloudQuery publishes new destination plugin versions (roughly weekly), our manifest falls behind. Manually checking 21 plugins for updates is error-prone and does not scale.

Similarly, the Go toolchain version declared in the manifest should track upstream releases, but not so aggressively that we adopt versions before they're proven stable.

We need automated pipelines that:
1. Detect new plugin versions and update the manifest
2. Track Go releases with a stabilization buffer
3. Produce auditable pull requests for human review

## Decision

### Plugin Updates (Daily)

A GitHub Actions workflow (`update-plugins.yaml`) runs daily at 06:00 UTC:

1. **Dry-run check**: Runs `scripts/update-plugins.sh --dry-run` to detect available updates
2. **Apply updates**: If updates exist, runs `scripts/update-plugins.sh` to modify `plugins.yaml`
3. **Validate**: Runs `make validate` to ensure all upstream references still resolve
4. **Detect new plugins**: Runs `scripts/detect-new-plugins.sh` to flag untracked destination plugins
5. **Create PR**: Uses `peter-evans/create-pull-request` to open a PR with the changes

### Go Version Updates (Weekly)

A GitHub Actions workflow (`update-go-version.yaml`) runs weekly on Mondays at 09:00 UTC:

1. **Check current**: Reads `go_version` from `plugins.yaml` metadata
2. **Update**: Runs `scripts/update-go-version.sh` which fetches the latest stable Go release ≥14 days old
3. **Validate**: Runs `make validate` to confirm the manifest is still valid
4. **Create PR**: Opens a PR if the version changed

### Authentication

Both workflows use a **GitHub App token** (`actions/create-github-app-token`) rather than `GITHUB_TOKEN` because:
- PRs created by `GITHUB_TOKEN` do not trigger other workflows (GitHub's anti-recursion protection)
- We need CI checks to run on the auto-generated PRs
- The app token has scoped permissions (contents: write, pull-requests: write) — no broader access

### PR Strategy

- **Single active PR per pipeline**: `peter-evans/create-pull-request` uses a fixed branch name (`auto/update-plugins` or `auto/update-go-version`) so subsequent runs update the same PR
- **Human review required**: PRs are not auto-merged — a team member must approve and merge
- **Commit message format**: Structured for easy parsing (e.g., `chore(deps): update destination plugins`)

## Alternatives Considered

### 1. Dependabot / Renovate
- **Pros**: Well-known, managed, supports many ecosystems
- **Cons**: Neither understands our custom `plugins.yaml` format or the CloudQuery fork's monorepo tag convention (`plugins-destination-<name>-v<version>`)
- **Rejected**: Would require custom extractors/managers — more complex than a purpose-built script

### 2. Auto-merge without human review
- **Pros**: Faster updates, less manual work
- **Cons**: A bad upstream release could break all builds; no opportunity to batch-review changes
- **Rejected**: Constitution requires traceability (Article II) — PR review provides an audit trail

### 3. `GITHUB_TOKEN` instead of App token
- **Pros**: No setup required, built into every workflow
- **Cons**: PRs created by `GITHUB_TOKEN` don't trigger CI — we'd have no automated checks on update PRs
- **Rejected**: Defeats the purpose of having CI validation on plugin updates

### 4. Cron-only (no manual dispatch)
- **Pros**: Simpler workflow definition
- **Cons**: Cannot trigger an update on-demand (e.g., after a critical upstream fix)
- **Rejected**: Both workflows support `workflow_dispatch` for manual triggering alongside their cron schedules

## Consequences

- **Positive**: Plugin versions stay current within 24 hours of upstream release
- **Positive**: Go version updates include a 14-day stabilization buffer, reducing risk of adopting buggy releases
- **Positive**: All updates go through PRs with CI validation — full audit trail
- **Positive**: New untracked plugins are surfaced automatically in workflow output and PR body
- **Positive**: Scripts are independently runnable (`--dry-run`, `--help`) for local testing
- **Negative**: Requires GitHub App setup (app ID + private key as repository secrets)
- **Negative**: Daily PR noise if upstream publishes frequently — mitigated by single-branch strategy (updates existing PR)
- **Negative**: `peter-evans/create-pull-request` is a third-party action — mitigated by SHA-pinning to audited version
