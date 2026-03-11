# traffic-gen

A configurable traffic generator that sends fake HTTP requests to echo-server.
Deployed as a Kubernetes CronJob via Helm — runs on a schedule to simulate
realistic traffic patterns for testing, monitoring, and validation.

## What It Does

Sends concurrent HTTP requests to a target service, rotating through endpoints
(`/`, `/healthz`, `/ready`). Logs every request with status and latency, then
prints a summary with pass/fail status.

```
=== Traffic Generator Results ===
Total:     50
Successes: 50
Failures:  0
Latency:   min=2ms avg=8ms max=45ms
STATUS: PASS
```

Exits with code 0 on success, 1 if any request fails — making it suitable for
CronJob health monitoring.

## Configuration

All configuration is via environment variables:

| Env Var       | Default                 | Description                           |
| ------------- | ----------------------- | ------------------------------------- |
| `TARGET_URL`  | `http://echo-server:80` | Base URL of the target service        |
| `REQUESTS`    | `100`                   | Total number of requests to send      |
| `CONCURRENCY` | `5`                     | Max concurrent requests               |
| `DELAY_MS`    | `100`                   | Delay between launching requests (ms) |

## Local Development

```sh
# Start echo-server first
cd ../echo-server && make run

# In another terminal, run traffic-gen against it
make run
# → sends 10 requests to localhost:8080
```

## Building

```sh
# Local binary
make build

# ARM64 container image
make docker-build

# Push to GHCR
make docker-push
```

## Helm Chart (CronJob)

The chart deploys traffic-gen as a CronJob. Default: every 15 minutes, 50 requests.

### Install Directly

```sh
helm install traffic-gen ./chart \
  --namespace dev \
  --set traffic.targetURL=http://echo-server.dev.svc.cluster.local:80
```

### Values

```yaml
# Schedule (cron format)
schedule: "*/15 * * * *"

# Traffic settings
traffic:
  targetURL: http://echo-server:80
  requests: 50
  concurrency: 5
  delayMs: 100

# Resource limits (Pi-friendly)
resources:
  requests:
    cpu: 5m
    memory: 8Mi
  limits:
    memory: 32Mi

# Job history
successfulJobsHistoryLimit: 3
failedJobsHistoryLimit: 3
```

### Per-Environment Overrides

Create overlays in `platform/overlays/traffic-gen/` to vary behavior per env:

```yaml
# values-dev.yaml — frequent, light traffic
schedule: "*/5 * * * *"
traffic:
  targetURL: http://echo-server.dev.svc.cluster.local:80
  requests: 20
  concurrency: 2

# values-staging.yaml — moderate, closer to real patterns
schedule: "*/10 * * * *"
traffic:
  targetURL: http://echo-server.staging.svc.cluster.local:80
  requests: 100
  concurrency: 10

# values-prod.yaml — infrequent, synthetic monitoring
schedule: "*/30 * * * *"
traffic:
  targetURL: http://echo-server.prod.svc.cluster.local:80
  requests: 10
  concurrency: 2
```

### Trigger a Manual Run

```sh
kubectl create job --from=cronjob/traffic-gen traffic-gen-manual -n dev
kubectl logs -f job/traffic-gen-manual -n dev
```

## Project Structure

```
traffic-gen/
├── cmd/traffic-gen/main.go     # Entrypoint: config, runner, summary
├── chart/                      # Helm chart (CronJob)
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── _helpers.tpl
│       └── cronjob.yaml
├── Dockerfile                  # Multi-stage → ~5MB distroless image
├── go.mod
└── Makefile
```
