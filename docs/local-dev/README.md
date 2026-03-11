# Local Development

Run and test the homelab services on your local machine without a Kubernetes cluster.

## Prerequisites

| Tool              | Install                                        | Verify           |
| ----------------- | ---------------------------------------------- | ---------------- |
| Go 1.22+          | `brew install go`                              | `go version`     |
| Helm              | `brew install helm`                            | `helm version`   |
| Docker (optional) | Docker Desktop or `brew install --cask docker` | `docker version` |

## Quick Start

Open two terminal windows:

**Terminal 1 — echo-server:**

```sh
cd apps/echo-server
make run
# → listening on :8080
```

**Terminal 2 — traffic-gen:**

```sh
cd apps/traffic-gen
make run
# → sends 10 requests to localhost:8080, prints summary
```

## Running echo-server

```sh
cd apps/echo-server
make run
```

Test it manually:

```sh
curl http://localhost:8080/
curl http://localhost:8080/healthz
curl http://localhost:8080/ready
```

Expected output from `/`:

```json
{
  "hostname": "your-machine",
  "timestamp": "2026-03-11T12:00:00Z",
  "method": "GET",
  "path": "/",
  "headers": { ... },
  "go": "go1.22.0",
  "arch": "arm64"
}
```

The server runs on port 8080 until you press Ctrl+C (graceful shutdown).

## Running traffic-gen

With echo-server running in another terminal:

```sh
cd apps/traffic-gen
make run
```

This sends 10 requests with concurrency 2 and 200ms delay. To customize:

```sh
cd apps/traffic-gen
TARGET_URL=http://localhost:8080 \
REQUESTS=50 \
CONCURRENCY=5 \
DELAY_MS=50 \
go run ./cmd/traffic-gen/
```

## Running Tests

### Unit Tests

```sh
# echo-server unit tests (handlers)
cd apps/echo-server
make test

# Run with verbose output
go test -v -race -count=1 ./...
```

Expected:

```
ok  github.com/aroethe/homelab/apps/echo-server/internal/handler  0.5s
```

### E2E Tests

E2E tests run against a live echo-server instance. Start the server first,
then run the tests in a second terminal.

**Terminal 1:**

```sh
cd apps/echo-server
make run
```

**Terminal 2:**

```sh
cd apps/echo-server
SERVICE_URL=http://localhost:8080 go test -tags e2e -v ./e2e/
```

The E2E suite covers:

- Health and readiness endpoints return 200
- Echo endpoint returns all required JSON fields
- Content-Type is `application/json`
- Request headers are forwarded in the response
- Correct HTTP method is echoed
- 50 concurrent requests with zero failures
- p99 latency under 500ms

### Helm Chart Validation

Lint and template-render all chart + overlay combinations (no cluster needed):

```sh
# From repo root
make validate-chart
```

This runs `helm lint` and `helm template` for each environment (dev, staging, prod).

### Go Vet

```sh
cd apps/echo-server && make vet
cd apps/traffic-gen && make vet
```

## All-in-One Test Script

Run everything from the repo root:

```sh
# Unit tests
make echo-test

# Chart validation
make validate-chart

# E2E (requires echo-server running on :8080 in another terminal)
cd apps/echo-server && SERVICE_URL=http://localhost:8080 go test -tags e2e -v ./e2e/
```

## Building Container Images

If you want to test the Docker builds locally (requires Docker):

```sh
# echo-server
cd apps/echo-server
make docker-build                   # ARM64 image
docker buildx build -t echo-server:local .   # native arch for local testing

# traffic-gen
cd apps/traffic-gen
make docker-build                   # ARM64 image
docker buildx build -t traffic-gen:local .   # native arch for local testing

# E2E test container
cd apps/echo-server
make e2e-build                      # ARM64 image
```

### Run containers locally

```sh
# Start echo-server
docker run --rm -p 8080:8080 echo-server:local

# Run traffic-gen against it
docker run --rm --network host \
  -e TARGET_URL=http://localhost:8080 \
  -e REQUESTS=20 \
  traffic-gen:local
```

## Project Layout

```
apps/
├── echo-server/              # HTTP echo service
│   ├── cmd/server/main.go    # Entrypoint
│   ├── internal/handler/     # Handlers + unit tests
│   ├── e2e/                  # E2E test suite (build tag: e2e)
│   ├── chart/                # Base Helm chart
│   ├── Dockerfile
│   └── Makefile
│
└── traffic-gen/              # Traffic generator (CronJob)
    ├── cmd/traffic-gen/      # Entrypoint
    ├── chart/                # Helm chart (CronJob)
    ├── Dockerfile
    └── Makefile
```

## Troubleshooting

**Port 8080 already in use:**

```sh
lsof -i :8080
# Kill the process or use a different port by editing cmd/server/main.go
```

**E2E tests fail with "connection refused":**

echo-server must be running before starting the E2E tests. Check terminal 1.

**`make run` fails for traffic-gen:**

Ensure echo-server is running on port 8080 first. traffic-gen exits with code 1
if any request fails.

**Helm lint warnings about icon:**

`[INFO] Chart.yaml: icon is recommended` is informational, not an error. Safe to ignore.
