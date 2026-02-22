# Contract: Update Plugins Script

**Feature**: 005-auto-update-dest-plugins
**Script**: `scripts/update-plugins.sh`

## Purpose

Queries the Infoblox fork for the latest stable release tag of each destination plugin in `plugins.yaml`, compares with the current version, and updates entries where a newer version is available.

## Interface

```bash
Usage: ./scripts/update-plugins.sh [OPTIONS]

Options:
  --dry-run     Report available updates without modifying files
  --commit      Create a git commit with the changes (for CI use)
  --help        Show usage
```

## Behaviour Contract

### Inputs

- `plugins.yaml` — current manifest (read from repo root)
- Git remote: `https://github.com/infobloxopen/cloudquery` — queried via `git ls-remote`

### Outputs

| Mode | File Changes | Stdout | Exit Code |
|------|-------------|--------|-----------|
| `--dry-run` | None | Table of current vs available versions | `0` (always) |
| Default (no flags) | Updates `plugins.yaml` in-place | Update log | `0` if no errors, `1` on failure |
| `--commit` | Updates `plugins.yaml` + creates git commit | Update log + commit SHA | `0` if no errors, `1` on failure |

### Version Selection Rules

1. Only stable tags are considered: `^plugins-destination-<name>-v\d+\.\d+\.\d+$`
2. Pre-release tags (`-rc`, `-beta`, `-alpha`) are ignored
3. Latest stable version is selected (highest semver)
4. **No downgrades**: if current version > latest tag, no change is made
5. Major version bumps update `ldflags_version_path` (replace `v<old>` with `v<new>`)

### Fields Updated per Plugin

When a newer version is detected:
- `version` → new version string
- `upstream.tag` → new tag string
- `upstream.commit` → commit SHA that the new tag resolves to (via `git ls-remote`)
- `build.ldflags_version_path` → updated if major version changes

### New Plugin Detection

After processing all existing plugins, the script queries for all `plugins-destination-*` tags in the fork and reports any plugin names not present in `plugins.yaml`:

```text
[WARN]  New plugins detected (not in manifest): redshift, timestream
```

These are logged but NOT auto-added.

### Error Handling

- Network failure on `git ls-remote`: retry up to 3 times with exponential backoff (1s, 2s, 4s)
- If all retries fail: exit with code `1` (no changes made)
- Invalid tag format: skip with warning
- `yq` not available: exit with code `1` immediately

### Commit Message Format

When `--commit` is used:

```text
chore: update plugin versions

Updated plugins:
  - postgresql: v8.14.1 → v8.15.0
  - kafka: v5.7.1 → v5.8.0

Signed-off-by: github-actions[bot] <github-actions[bot]@users.noreply.github.com>
```

If no updates are found, no commit is created.

## Dependencies

- `yq` (v4+) — YAML manipulation
- `git` — `git ls-remote` for tag resolution
- `sort` — with `-V` flag for semver comparison (GNU coreutils)
- `sed`, `grep` — text processing

## CI Workflow Integration

The daily CI workflow (`update-plugins.yaml`) calls:

```yaml
- name: Check for updates
  id: update
  run: ./scripts/update-plugins.sh --dry-run

- name: Apply updates
  if: steps.update.outputs.has_updates == 'true'
  run: ./scripts/update-plugins.sh

- name: Validate
  if: steps.update.outputs.has_updates == 'true'
  run: make validate

- name: Create Pull Request
  if: steps.update.outputs.has_updates == 'true'
  uses: peter-evans/create-pull-request@<sha>
  with:
    token: ${{ steps.app-token.outputs.token }}
    title: "chore: update plugin versions"
    branch: update/plugins-${{ github.run_id }}
    delete-branch: true
```
