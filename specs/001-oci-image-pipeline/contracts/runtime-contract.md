# OCI Image Runtime Contract

**Feature**: 001-oci-image-pipeline
**Date**: 2026-02-12

## Image Runtime Behaviour

Every published OCI image MUST conform to this contract.

### Default Entrypoint

```
ENTRYPOINT ["/entrypoint"]
CMD ["serve", "--address", "[::]:7777", "--log-format", "json", "--log-level", "info"]
```

The `/entrypoint` binary is a thin Go wrapper that:
1. Reads `CQ_PLUGIN_ADDRESS` (default: `[::]`) and `CQ_PLUGIN_PORT` (default: `7777`)
2. If either env var is set, constructs `--address <addr>:<port>` and prepends it to the args
3. Execs `/plugin <args...>`

### Environment Variable Overrides

| Env Var | Default | Effect |
|---------|---------|--------|
| `CQ_PLUGIN_ADDRESS` | `[::]` | Overrides the bind address |
| `CQ_PLUGIN_PORT` | `7777` | Overrides the bind port |

Example: `CQ_PLUGIN_PORT=9090` → plugin serves on `[::]:9090`

### Exposed Port

- **Protocol**: gRPC (HTTP/2)
- **Default port**: 7777
- **Bind address**: `[::]` (all interfaces, IPv4 + IPv6)

### User / Security

- Runs as non-root user (UID 65534 / `nonroot` from distroless)
- Image supports `readOnlyRootFilesystem: true`
- Image supports `drop: [ALL]` capabilities
- Writable directory: `/tmp` (must be provided as `emptyDir` volume in k8s if plugin writes temporary files)

### Filesystem Layout

```
/plugin          # Plugin binary (statically linked)
/entrypoint      # Entrypoint wrapper binary
/licenses/       # Upstream MPL-2.0 license file(s)
/tmp/            # Writable scratch directory (if mounted)
```

### Health Check

- No HTTP health endpoint (gRPC only)
- Health is verified by TCP connectivity on the gRPC port
- Kubernetes `tcpSocket` liveness/readiness probes are recommended

### OCI Labels

See data-model.md § OCI Image for the full label set.
