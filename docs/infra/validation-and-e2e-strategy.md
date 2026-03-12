# Validation and E2E Testing Strategy

Application-level validation gates that get stricter as code moves through
environments. Infrastructure (ArgoCD, Kargo, cert-manager) already validates
itself via built-in mechanisms — this doc focuses on **your application code**.

## Built-in Infrastructure Validation (already handled)

These are not our concern — they're handled by the tools themselves:

| Tool             | Built-in Validation                                       | We Do Nothing                                                |
| ---------------- | --------------------------------------------------------- | ------------------------------------------------------------ |
| **ArgoCD**       | Sync status, health checks, auto-heal, degraded detection | ArgoCD won't report Healthy until pods pass readiness probes |
| **Kargo**        | Freight tracking, Stage health, promotion prerequisites   | Won't promote to staging until dev Stage reports healthy     |
| **k3s**          | kubelet liveness/readiness probes, pod restart policies   | Restarts unhealthy containers automatically                  |
| **Helm**         | Release status, rollback on failed install/upgrade        | ArgoCD handles this via sync                                 |
| **cert-manager** | Certificate ready conditions, auto-renewal                | Self-healing                                                 |

**We don't wrap these.** If ArgoCD says the app is Synced + Healthy, the
infrastructure is doing its job. Our validation is about: **does the application
actually work correctly?**

## Application Gate Strategy

```mermaid
flowchart LR
    subgraph dev["Dev Gate — Fast Feedback"]
        unit["Unit tests"]
        lint["go vet + lint"]
        health["Health check"]
    end

    subgraph staging["Staging Gate — Full E2E"]
        e2e["E2E test suite"]
        contract["API contract tests"]
        perf["Basic load test"]
    end

    subgraph prod["Prod Gate — PR Approval"]
        prod_pr["GH Action opens PR"]
        merge["Developer merges PR"]
        argocd_sync["ArgoCD syncs prod"]
    end

    dev -->|"auto-promote<br/>if all pass"| staging
    staging -->|"staging updated<br/>on master"| prod
```

| Environment | Gate Philosophy            | Test Type                              | Runs In                                 |
| ----------- | -------------------------- | -------------------------------------- | --------------------------------------- |
| **Dev**     | Fast, catch obvious breaks | Unit tests + health check              | CI + Kargo verification Job             |
| **Staging** | Thorough, catch real bugs  | E2E test suite against live deployment | Kargo verification Job (test container) |
| **Prod**    | Safe, PR-gated deploy      | PR approval + ArgoCD auto-sync         | GH Action opens PR, merge = deploy      |

## Dev Gate: Fast Feedback

Goal: catch compilation errors, broken logic, and crashed processes in under 60 seconds.

```mermaid
flowchart TD
    push["Stable release tag pushed to GHCR"] --> warehouse["Kargo Warehouse detects tag"]
    warehouse --> promote["Kargo promotes to dev<br/>(updates demo/dev/echo-server.yaml, ArgoCD syncs)"]
    promote --> argocd["ArgoCD waits for<br/>readiness probe to pass"]
    argocd --> verify["Kargo Verification Job"]

    subgraph verify_steps["Dev Verification"]
        health_check["curl /healthz → 200"]
        echo_check["curl / → valid JSON with<br/>hostname, arch, timestamp"]
    end

    verify --> verify_steps
    verify_steps -->|"pass"| verified["Freight verified in dev<br/>→ eligible for staging"]
    verify_steps -->|"fail"| blocked["Promotion chain stops"]
```

### What Runs Before the Image is Built

Unit tests and linting run **before** the image is pushed. This is CI or local
`make test`:

```
apps/echo-server/
├── cmd/server/
│   └── main.go
├── internal/
│   └── handler/
│       ├── handler.go          # Extract handlers from main
│       └── handler_test.go     # Unit tests
├── go.mod
├── Makefile
└── Dockerfile
```

The echo-server Makefile `test` target runs `go test ./...` with race detection.
The `echo-release` target should run tests first:

```makefile
echo-release: echo-test       ## Build + push (tests must pass first)
echo-test:                    ## Run unit tests
    cd apps/echo-server && go test -race -count=1 ./...
```

### Kargo Dev Verification

After ArgoCD deploys and reports healthy, Kargo runs a lightweight
verification Job — just confirm the service responds correctly:

```yaml
# tests/kargo/echo-server-dev-verify.yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: echo-server-dev-verify
  namespace: echo-server
spec:
  metrics:
    - name: health-check
      provider:
        job:
          spec:
            backoffLimit: 1
            activeDeadlineSeconds: 30
            ttlSecondsAfterFinished: 120
            template:
              spec:
                restartPolicy: Never
                containers:
                  - name: verify
                    image: curlimages/curl:latest
                    imagePullPolicy: IfNotPresent
                    resources:
                      requests: { cpu: 5m, memory: 8Mi }
                      limits: { memory: 16Mi }
                    command: [sh, -c]
                    args:
                      - |
                        set -e
                        SVC="http://echo-server.dev.svc.cluster.local:80"
                        for i in 1 2 3; do
                          curl -sf --max-time 5 "$SVC/healthz" && break
                          sleep 3
                        done
                        curl -sf "$SVC/healthz" | grep -q '"status":"ok"'
                        curl -sf "$SVC/" | grep -q '"hostname"'
                        echo "dev gate passed"
```

Added to `stage-dev.yaml`:

```yaml
verification:
  analysisTemplates:
    - name: echo-server-dev-verify
```

**Time budget: ~15 seconds.**

## Staging Gate: Full E2E Test Suite

Goal: run a real test suite against the live staging deployment. This is where
you catch integration bugs, API contract violations, and regressions.

```mermaid
flowchart TD
    freight["Freight verified in dev"] --> promote["Kargo promotes to staging"]
    promote --> argocd["ArgoCD deploys + healthy"]
    argocd --> verify["Kargo Verification Job"]

    subgraph verify_steps["Staging Verification — E2E Test Container"]
        api["API contract tests<br/>all endpoints return expected schemas"]
        behavior["Behavioral tests<br/>echo returns request data correctly<br/>headers are forwarded<br/>content-type is application/json"]
        edge["Edge case tests<br/>unknown routes return 404<br/>large headers handled<br/>concurrent requests"]
        load["Basic load test<br/>50 concurrent requests<br/>p99 latency < 500ms<br/>zero errors"]
    end

    verify --> verify_steps
    verify_steps -->|"all pass"| verified["Freight verified in staging<br/>→ eligible for prod"]
    verify_steps -->|"any fail"| blocked["Promotion to prod blocked"]
```

### E2E Test Container

The test suite is a Go test binary packaged as a container image. It runs as a
Kargo verification Job against the staging service.

```
apps/echo-server/
├── e2e/
│   ├── e2e_test.go             # Full E2E test suite
│   ├── Dockerfile              # Packages tests as a container
│   └── Makefile
```

**`e2e/e2e_test.go`** — tests run against the service URL passed via env var:

```go
// Tests run against a live deployment via SERVICE_URL env var
package e2e

import (
    "encoding/json"
    "net/http"
    "sync"
    "testing"
    "os"
)

var serviceURL = os.Getenv("SERVICE_URL")

func TestHealthEndpoint(t *testing.T) {
    resp, err := http.Get(serviceURL + "/healthz")
    // assert 200, body contains {"status":"ok"}
}

func TestEchoEndpoint(t *testing.T) {
    resp, err := http.Get(serviceURL + "/")
    // assert 200, JSON has hostname, timestamp, arch, headers, method, path
}

func TestEchoReturnsRequestHeaders(t *testing.T) {
    req, _ := http.NewRequest("GET", serviceURL+"/", nil)
    req.Header.Set("X-Test-Header", "hello")
    // assert response.headers contains X-Test-Header
}

func TestReadinessEndpoint(t *testing.T) {
    resp, err := http.Get(serviceURL + "/ready")
    // assert 200
}

func TestUnknownRouteReturns404(t *testing.T) {
    resp, err := http.Get(serviceURL + "/does-not-exist")
    // assert 404
}

func TestContentTypeIsJSON(t *testing.T) {
    resp, err := http.Get(serviceURL + "/")
    // assert Content-Type: application/json
}

func TestConcurrentRequests(t *testing.T) {
    var wg sync.WaitGroup
    errors := make(chan error, 50)
    for i := 0; i < 50; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            resp, err := http.Get(serviceURL + "/")
            // collect errors
        }()
    }
    // assert zero errors, all 200s
}

func TestResponseLatency(t *testing.T) {
    // 10 sequential requests, assert p99 < 500ms
}
```

**`e2e/Dockerfile`**:

```dockerfile
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod go.sum* ./
RUN go mod download 2>/dev/null || true
COPY . .
RUN CGO_ENABLED=0 go test -c -o /e2e-tests ./e2e/

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /e2e-tests /e2e-tests
ENTRYPOINT ["/e2e-tests", "-test.v"]
```

### Kargo Staging Verification

The verification Job runs the E2E test container against the staging service:

```yaml
# tests/kargo/echo-server-staging-verify.yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: echo-server-staging-verify
  namespace: echo-server
spec:
  metrics:
    - name: e2e-tests
      provider:
        job:
          spec:
            backoffLimit: 0
            activeDeadlineSeconds: 120
            ttlSecondsAfterFinished: 300
            template:
              spec:
                restartPolicy: Never
                containers:
                  - name: e2e
                    image: ghcr.io/aroethe/homelab/echo-server-e2e:latest
                    imagePullPolicy: Always
                    resources:
                      requests: { cpu: 10m, memory: 32Mi }
                      limits: { memory: 64Mi }
                    env:
                      - name: SERVICE_URL
                        value: http://echo-server.staging.svc.cluster.local:80
```

Added to `stage-staging.yaml`:

```yaml
verification:
  analysisTemplates:
    - name: echo-server-staging-verify
```

**Time budget: ~30-60 seconds.** Includes test compilation (if not pre-compiled),
all API contract checks, concurrent load, and latency assertions.

### Building the E2E Image

```makefile
# In apps/echo-server/Makefile
e2e-build:          ## Build E2E test container (ARM64)
    docker buildx build --platform linux/arm64 -t $(REGISTRY)/echo-server-e2e:latest -f e2e/Dockerfile .

e2e-push:           ## Build and push E2E test container
    docker buildx build --platform linux/arm64 -t $(REGISTRY)/echo-server-e2e:latest -f e2e/Dockerfile --push .
```

The E2E image is rebuilt whenever tests change. It doesn't need to be versioned
with semver — `latest` is fine since the tests validate the _deployed_ service,
not themselves.

## Prod Gate: PR-Gated Deployment

Goal: require explicit human approval before deploying to production. The
approval mechanism is a GitHub PR — reviewing and merging the PR deploys to prod.

```mermaid
flowchart TD
    freight["Freight verified in staging<br/>(E2E suite passed)"] --> staging_update["Kargo updates staging file on master"]
    staging_update --> gh_action["promote-prod.yaml GH Action triggers"]
    gh_action --> pr["Opens PR: promote(prod): echo-server vX.Y.Z"]
    pr -->|"developer reviews + merges"| argocd["ArgoCD auto-syncs prod"]
    argocd --> done["Prod deployment complete"]
```

### Why Prod is Different

Prod doesn't use Kargo for promotion. Instead:

1. Kargo handles dev → staging automatically (with verification)
2. When staging is updated on master, a GH Action opens a PR to update prod
3. The PR is the approval gate — merging it deploys to prod
4. ArgoCD's `selfHeal: true` keeps prod in sync with master

This gives you:

- Code review on prod deployments (PR diff shows exactly what changes)
- Audit trail via PR history
- Easy rollback by reverting the PR
- No need for Kargo UI access to approve prod

### Rollback

If something goes wrong in production:

1. **Revert PR**: Revert the promotion PR on GitHub — ArgoCD syncs immediately
2. **New release**: Fix the issue, cut a new release, let it flow through the pipeline
3. **Emergency**: Manually update `platform/apps/demo/prod/echo-server.yaml`
   to pin a known-good tag, push to master

## Summary: Gate Comparison

```mermaid
graph TB
    subgraph dev["DEV"]
        d1["Unit tests (pre-build)"]
        d2["go vet + lint (pre-build)"]
        d3["Health check (post-deploy)"]
        d_time["~15 seconds"]
    end

    subgraph staging["STAGING"]
        s1["Full E2E test suite (post-deploy)"]
        s2["API contract validation"]
        s3["Concurrent load test (50 req)"]
        s4["Latency assertion (p99 < 500ms)"]
        s_time["~30-60 seconds"]
    end

    subgraph prod["PROD"]
        p0["GH Action opens PR"]
        p1["Developer reviews + merges"]
        p2["ArgoCD auto-syncs"]
        p_time["PR review + merge"]
    end

    dev -->|"auto"| staging
    staging -->|"PR gate"| prod
```

|                 | Dev                             | Staging                                 | Prod                          |
| --------------- | ------------------------------- | --------------------------------------- | ----------------------------- |
| **Pre-build**   | `go test -race ./...`, `go vet` | —                                       | —                             |
| **Post-deploy** | curl health + echo check        | Full E2E test container                 | —                             |
| **Promotion**   | Auto                            | Auto (if E2E passes)                    | PR merge (GH Action opens PR) |
| **On failure**  | Blocks staging                  | Blocks prod PR                          | Revert PR, ArgoCD syncs back  |
| **Runs as**     | Kargo verification Job (curl)   | Kargo verification Job (Go test binary) | GitHub PR + ArgoCD auto-sync  |
| **Time**        | ~15s                            | ~30-60s                                 | PR review time                |

## File Structure

```
apps/echo-server/
├── cmd/server/main.go
├── internal/handler/
│   ├── handler.go              # Extracted handlers (testable)
│   └── handler_test.go         # Unit tests
├── e2e/
│   ├── e2e_test.go             # Full E2E suite (runs against live service)
│   └── Dockerfile              # Packages tests as container
├── Dockerfile
├── go.mod
└── Makefile                    # test, e2e-build, e2e-push targets

tests/kargo/
├── echo-server-dev-verify.yaml       # AnalysisTemplate: curl health check
└── echo-server-staging-verify.yaml   # AnalysisTemplate: E2E test container
```

## Makefile Targets

```
## --- App Testing ---
echo-test            Run unit tests (go test -race ./...)
echo-e2e-build       Build E2E test container (ARM64)
echo-e2e-push        Build and push E2E test container
echo-release         Build + push app image (runs echo-test first)

## --- Kargo Verification ---
kargo-verification   Apply all verification AnalysisTemplates

## --- Manual Smoke ---
smoke-dev            Smoke test dev from dev machine
smoke-staging        Smoke test staging from dev machine
smoke-prod           Smoke test prod from dev machine

## --- Validation ---
validate-chart       Helm lint + template + kubeconform
```

## Implementation Order

1. Extract handlers into `internal/handler/` and write unit tests
2. Add `echo-test` target, wire `echo-release` to depend on it
3. Create `tests/kargo/echo-server-dev-verify.yaml` — curl-based health check
4. Add `verification` stanza to `stage-dev.yaml`
5. Write `e2e/e2e_test.go` test suite and `e2e/Dockerfile`
6. Create `tests/kargo/echo-server-staging-verify.yaml` — E2E test container
7. Add `verification` stanza to `stage-staging.yaml`
8. Set up `promote-prod.yaml` GH Action for PR-gated prod promotion
9. Add all Makefile targets
