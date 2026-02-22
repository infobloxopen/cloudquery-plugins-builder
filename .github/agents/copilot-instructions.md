# cloudquery-plugins-builder Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-02-12

## Active Technologies
- Bash (scripts), GitHub Actions YAML (CI), Make (build targets), Go 1.25+ (entrypoint — unchanged) + `yq` (YAML processing), Docker Buildx, `cosign`, GitHub Actions (`docker/build-push-action`) (003-rename-dest-images)
- N/A — no data persistence; OCI images are pushed to GHCR (003-rename-dest-images)
- Bash scripts, Dockerfile, YAML configuration — no application code changes + Docker Buildx, yq, jq, git (all pre-existing) (004-use-fork-repo)
- Bash scripts, Dockerfile (multi-stage), YAML manifests — no application code changes + Docker Buildx, yq, jq, git (all pre-existing; no new dependencies) (004-use-fork-repo)
- Bash (update/detection scripts); Go 1.25.6 (existing entrypoint — unchanged); YAML (manifest, CI workflows) + yq, jq, git (ls-remote), Docker Buildx, GitHub Actions, curl (Go version API) (005-auto-update-dest-plugins)
- N/A (images in GHCR; manifest in-repo; build index as JSON artifact) (005-auto-update-dest-plugins)

- Go 1.25.6 (plugins + entrypoint wrapper); Bash (scripts); JSON Schema (validation) + Docker Buildx, QEMU, cosign, yq, jq, GitHub Actions (001-oci-image-pipeline)

## Project Structure

```text
src/
tests/
```

## Commands

# Add commands for Go 1.25.6 (plugins + entrypoint wrapper); Bash (scripts); JSON Schema (validation)

## Code Style

Go 1.25.6 (plugins + entrypoint wrapper); Bash (scripts); JSON Schema (validation): Follow standard conventions

## Recent Changes
- 005-auto-update-dest-plugins: Added Bash (update/detection scripts); Go 1.25.6 (existing entrypoint — unchanged); YAML (manifest, CI workflows) + yq, jq, git (ls-remote), Docker Buildx, GitHub Actions, curl (Go version API)
- 004-use-fork-repo: Added Bash scripts, Dockerfile (multi-stage), YAML manifests — no application code changes + Docker Buildx, yq, jq, git (all pre-existing; no new dependencies)
- 004-use-fork-repo: Added Bash scripts, Dockerfile (multi-stage), YAML manifests — no application code changes + Docker Buildx, yq, jq, git (all pre-existing; no new dependencies)


<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
