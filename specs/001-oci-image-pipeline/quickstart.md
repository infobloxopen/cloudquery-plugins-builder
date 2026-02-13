# Quickstart: OCI Image Pipeline for CloudQuery Plugins

**Feature**: 001-oci-image-pipeline
**Date**: 2026-02-12

## Prerequisites

- Docker (with Buildx enabled)
- `yq` (YAML processor)
- `jq` (JSON processor)
- Go 1.25.6+ (for local plugin builds)
- A Kubernetes cluster (for deployment testing) — Kind or Minikube work fine

## 1. Clone the Repository

```bash
git clone https://github.com/infobloxopen/cloudquery-plugins-builder.git
cd cloudquery-plugins-builder
```

## 2. Review the Manifest

```bash
cat plugins.yaml
```

The manifest lists all plugins to build. MVP includes:
- `postgresql` destination v8.14.1
- `s3` destination v7.10.2
- `file` destination v5.5.1

## 3. Build a Single Plugin Locally

```bash
# Build the postgresql plugin image for your local architecture
make build PLUGIN=postgresql

# Or equivalently:
./scripts/build.sh postgresql
```

This will:
1. Clone the upstream repo at the pinned tag
2. Build the Go binary with `CGO_ENABLED=0`
3. Package it into a minimal OCI image
4. Tag it as `cloudquery-plugin-postgresql:v8.14.1`

## 4. Run the Smoke Test

```bash
# Run the built image and verify gRPC port is listening
make smoke-test PLUGIN=postgresql

# Or manually:
docker run -d --name smoke-postgresql cloudquery-plugin-postgresql:v8.14.1
./scripts/smoke-test.sh smoke-postgresql 7777 30
docker rm -f smoke-postgresql
```

Expected output: `PASS: port 7777 is accepting connections`

## 5. Build All Plugins

```bash
make build-all
```

## 6. Deploy to Kubernetes (Example)

```bash
# Deploy the postgresql plugin as a gRPC server
kubectl apply -f examples/postgresql/deployment.yaml

# Wait for it to be ready
kubectl wait --for=condition=ready pod -l app=cloudquery-plugin-postgresql --timeout=60s

# Run a CloudQuery sync job that uses the plugin
kubectl apply -f examples/postgresql/sync-job.yaml
kubectl logs -f job/cloudquery-sync-postgresql
```

## 7. Validate Manifest Schema

```bash
make validate-manifest
```

## 8. CI Workflow (automated)

Push changes to `plugins.yaml` → open a PR → CI validates → merge → images published to GHCR.

See `contracts/ci-workflows.md` for the full CI pipeline description.

## Key Files

| File | Purpose |
|------|---------|
| `plugins.yaml` | Plugin/version manifest (source of truth) |
| `schemas/plugins-manifest.schema.json` | JSON Schema for manifest validation |
| `Dockerfile` | Generic multi-stage Dockerfile for Go plugins |
| `cmd/entrypoint/main.go` | Entrypoint wrapper (env var → CLI flag bridge) |
| `scripts/build.sh` | Local build script |
| `scripts/smoke-test.sh` | TCP port smoke test |
| `scripts/validate-manifest.sh` | Manifest schema + upstream ref validation |
| `scripts/generate-build-index.sh` | Build index generation |
| `examples/<plugin>/` | Kubernetes deployment examples per plugin |
| `docs/build-index.md` | Human-readable build index |
| `Makefile` | Developer-facing targets |
