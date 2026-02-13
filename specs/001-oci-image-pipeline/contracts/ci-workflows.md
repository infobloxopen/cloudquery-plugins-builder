# CI Workflow Contract

**Feature**: 001-oci-image-pipeline
**Date**: 2026-02-12

## Workflow 1: PR Validation (`pr-validate.yaml`)

**Trigger**: `pull_request` targeting `main` (when `plugins.yaml`, `Dockerfile`, `scripts/**`, `.github/workflows/**` change)

**Permissions**: `contents: read`

**Steps** (per matrix entry):

```
1. Checkout this repo
2. Validate plugins.yaml against JSON Schema
3. For each plugin in manifest:
   a. Verify upstream tag exists (git ls-remote)
   b. Verify upstream commit matches tag (git ls-remote)
4. Build image (docker buildx build, no push)
5. Smoke test:
   a. docker run -d --name smoke-<name> <image>
   b. Wait up to 30s for TCP connection on port 7777
   c. docker logs smoke-<name> (capture for debugging)
   d. docker rm -f smoke-<name>
6. Report pass/fail per plugin
```

**Outputs**: Pass/fail status per plugin. No images pushed.

---

## Workflow 2: Main Branch Publish (`publish.yaml`)

**Trigger**: `push` to `main` (when `plugins.yaml` changes)

**Permissions**: `contents: write`, `packages: write`, `id-token: write` (for OIDC/cosign)

**Steps** (per matrix entry):

```
1. Checkout this repo
2. Validate plugins.yaml against JSON Schema
3. For each plugin in matrix:
   a. Checkout upstream repo at pinned tag
   b. Verify commit SHA matches
   c. Build multi-arch image (linux/amd64, linux/arm64)
      - --sbom=true --provenance=mode=max
      - OCI labels injected via --label
   d. Push to GHCR
   e. Sign with cosign (keyless, OIDC)
   f. Record digest + metadata
4. Aggregate build-index.json from all matrix jobs
5. Upload build-index.json as workflow artifact
6. Update docs/build-index.md (commit to main)
```

**Outputs**: Published images in GHCR, build-index.json artifact, updated docs.

---

## Workflow 3: Upstream Update Check (`check-updates.yaml`) — Optional / Enhancement

**Trigger**: `schedule` (weekly cron) or `workflow_dispatch`

**Permissions**: `contents: write`, `pull-requests: write`

**Steps**:

```
1. For each plugin in plugins.yaml:
   a. Query upstream repo for latest tag matching plugin pattern
   b. Compare with current manifest version
   c. If newer version exists:
      i.  Resolve tag to commit SHA
      ii. Update plugins.yaml entry
2. If any updates found:
   a. Create branch: update/<date>
   b. Commit updated plugins.yaml
   c. Open PR with changelog of version bumps
```

**Outputs**: PR with manifest updates (if newer versions detected).

---

## Matrix Generation

All workflows generate their build matrix by parsing `plugins.yaml`:

```bash
# Pseudo-code for matrix generation
yq -o json '.plugins[] | {name, kind, version, "upstream_tag": .upstream.tag}' plugins.yaml \
  | jq -s '{include: .}'
```

This produces a GitHub Actions matrix like:
```json
{
  "include": [
    {"name": "s3", "kind": "destination", "version": "v7.10.2", "upstream_tag": "plugins-destination-s3-v7.10.2"},
    {"name": "file", "kind": "destination", "version": "v5.5.1", "upstream_tag": "plugins-destination-file-v5.5.1"},
    {"name": "postgresql", "kind": "destination", "version": "v8.14.1", "upstream_tag": "plugins-destination-postgresql-v8.14.1"}
  ]
}
```

## Third-Party Actions (pinned to commit SHA)

| Action | Purpose |
|--------|---------|
| `actions/checkout` | Checkout repos |
| `docker/setup-buildx-action` | Install Buildx |
| `docker/setup-qemu-action` | QEMU for multi-arch |
| `docker/login-action` | Authenticate to GHCR |
| `docker/build-push-action` | Build + push + attestations |
| `docker/metadata-action` | Generate OCI labels |
| `sigstore/cosign-installer` | Install cosign |
| `actions/upload-artifact` | Publish build index |
