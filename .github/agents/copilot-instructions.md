# cloudquery-plugins-builder Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-02-12

## Active Technologies
- Bash (scripts), GitHub Actions YAML (CI), Make (build targets), Go 1.25+ (entrypoint — unchanged) + `yq` (YAML processing), Docker Buildx, `cosign`, GitHub Actions (`docker/build-push-action`) (003-rename-dest-images)
- N/A — no data persistence; OCI images are pushed to GHCR (003-rename-dest-images)

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
- 003-rename-dest-images: Added Bash (scripts), GitHub Actions YAML (CI), Make (build targets), Go 1.25+ (entrypoint — unchanged) + `yq` (YAML processing), Docker Buildx, `cosign`, GitHub Actions (`docker/build-push-action`)

- 001-oci-image-pipeline: Added Go 1.25.6 (plugins + entrypoint wrapper); Bash (scripts); JSON Schema (validation) + Docker Buildx, QEMU, cosign, yq, jq, GitHub Actions

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
