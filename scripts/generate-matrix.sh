#!/usr/bin/env bash
# generate-matrix.sh — Parse plugins.yaml and produce GitHub Actions matrix JSON.
#
# Usage: ./scripts/generate-matrix.sh [--manifest FILE]
#
# Output: JSON object suitable for GHA matrix strategy, e.g.:
#   {"include": [{"name": "s3", "kind": "destination", "version": "v7.10.2", ...}]}
set -euo pipefail

MANIFEST="${1:-plugins.yaml}"

# ─── Dependency check ─────────────────────────────────────────────────────────
for cmd in yq jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: Required command '$cmd' not found." >&2
    exit 1
  fi
done

# ─── Generate matrix ──────────────────────────────────────────────────────────
# Extract each plugin's fields into a flat JSON object per entry.
yq -o json '.plugins[]' "$MANIFEST" \
  | jq -s '{
      include: [
        .[] | {
          name: .name,
          kind: .kind,
          version: .version,
          upstream_repo: .upstream.repo,
          upstream_tag: .upstream.tag,
          upstream_commit: .upstream.commit,
          plugin_dir: .build.plugin_dir,
          go_version: .build.go_version,
          bin_name: (.build.bin_name // "plugin"),
          ldflags_version_path: (.build.ldflags_version_path // ""),
          cgo_required: (.build.cgo_required // false),
          publish: (.publish // true)
        }
      ]
    }'
