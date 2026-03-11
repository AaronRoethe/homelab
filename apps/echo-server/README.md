# echo-server

A lightweight Go HTTP service that echoes request metadata as JSON. Used as the
starter application for the homelab Kubernetes platform — validates the full
pipeline from code to running pod across dev, staging, and prod environments.

## API

| Method | Path       | Description           | Response                                                               |
| ------ | ---------- | --------------------- | ---------------------------------------------------------------------- |
| `GET`  | `/`        | Echo request metadata | JSON with hostname, timestamp, method, path, headers, Go version, arch |
| `GET`  | `/healthz` | Liveness probe        | `{"status":"ok"}`                                                      |
| `GET`  | `/ready`   | Readiness probe       | `{"status":"ok"}`                                                      |

### Example Response

```
GET /
```

```json
{
  "hostname": "echo-server-7d4b8c9f5-xk2m9",
  "timestamp": "2026-03-11T12:00:00Z",
  "method": "GET",
  "path": "/",
  "headers": {
    "Accept": ["*/*"],
    "User-Agent": ["curl/8.1.0"]
  },
  "go": "go1.22.0",
  "arch": "arm64"
}
```

## Project Structure

```
echo-server/
├── cmd/server/main.go              # Entrypoint: server setup + graceful shutdown
├── internal/handler/
│   ├── handler.go                  # HTTP handlers (echo, health)
│   └── handler_test.go             # Unit tests
├── e2e/
│   ├── e2e_test.go                 # E2E test suite (build tag: e2e)
│   └── Dockerfile                  # Packages tests as container for Kargo verification
├── chart/                          # Base Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
├── Dockerfile                      # Multi-stage build → ~7MB distroless image
├── go.mod
└── Makefile
```

## Local Development

```sh
# Run locally
make run
# → listening on :8080

# In another terminal
curl http://localhost:8080/
curl http://localhost:8080/healthz
```

## Testing

```sh
# Unit tests (fast, no dependencies)
make test

# Lint
make vet

# E2E tests (requires a running instance)
SERVICE_URL=http://localhost:8080 go test -tags e2e -v ./e2e/
```

## Building

```sh
# Local binary
make build

# ARM64 container image
make docker-build

# Push to GHCR
make docker-push

# Push with semver tag (for Kargo promotion)
make docker-push TAG=0.1.0
```

## E2E Test Container

The E2E suite is packaged as a container for use as a Kargo staging verification
Job. It runs against a live service via the `SERVICE_URL` environment variable.

```sh
# Build the test container
make e2e-build

# Push to registry
make e2e-push
```

Tests include: API contract validation, header forwarding, concurrent load
(50 requests), and latency assertions (p99 < 500ms).

## Deployment

This app is deployed via ArgoCD + Kargo. The base chart lives in `chart/`,
and per-environment overlays live in `platform/overlays/echo-server/`.

```
make echo-release VERSION=0.1.0   # from repo root — runs tests, builds, pushes
```

Kargo detects the new tag and promotes: dev (auto) → staging (auto) → prod (manual).

## Configuration

| Env Var | Default | Description                                             |
| ------- | ------- | ------------------------------------------------------- |
| —       | `:8080` | Listen address (hardcoded, change in main.go if needed) |

The server has no external dependencies — no database, no config files. It starts
in ~10ms and uses ~10MB of RAM.
