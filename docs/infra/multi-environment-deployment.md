# Multi-Environment Deployment with Kargo

Progressive delivery across dev → staging → prod on a single Raspberry Pi, using
Kargo as the GitOps promotion engine on top of ArgoCD.

## Overview

"Environments" are Kubernetes namespaces on the same k3s cluster. The patterns
(Warehouse → Stage → Promotion) are identical to multi-cluster setups — when you
outgrow the Pi, you change ArgoCD Application `destination.server` values and
everything else stays the same.

```
┌─────────────┐
│  GHCR Image  │
│  Registry    │
└──────┬───────┘
       │ polls for new tags
┌──────▼───────┐
│   Warehouse  │  Kargo: detects new image versions
└──────┬───────┘
       │ creates Freight
┌──────▼───────┐     ┌──────────────┐     ┌──────────────┐
│  Stage: dev  │────▶│Stage: staging│────▶│  Stage: prod │
│  (auto)      │     │  (auto)      │     │  (manual)    │
└──────┬───────┘     └──────┬───────┘     └──────┬───────┘
       │                    │                    │
       ▼                    ▼                    ▼
  ns: dev              ns: staging          ns: prod
  echo-server-dev      echo-server-staging  echo-server-prod
  (ArgoCD App)         (ArgoCD App)         (ArgoCD App)
```

## Resource Budget

| Component                              | RAM           | Notes                                      |
| -------------------------------------- | ------------- | ------------------------------------------ |
| Existing (OS + k3s + ArgoCD + Traefik) | ~1,380 MB     | Already running                            |
| cert-manager (3 pods)                  | ~200 MB       | Required by Kargo for webhook TLS          |
| Kargo (4 pods)                         | ~400 MB       | controller, api, mgmt-controller, webhooks |
| 3x echo-server (dev/staging/prod)      | ~96 MB        | 32 MB each                                 |
| **Total**                              | **~2,076 MB** |                                            |
| **Remaining for future workloads**     | **~5,900 MB** |                                            |

## Prerequisites

- Working k3s + ArgoCD (from initial setup)
- Container registry (GHCR) with push access
- GitHub Personal Access Token (for Kargo to commit tag updates)

## Directory Structure

New and modified paths relative to repo root:

```
platform/
├── cert-manager/
│   └── install/
│       ├── kustomization.yaml          # Kustomize on upstream manifest
│       └── patches/
│           └── resource-limits.yaml    # Pi-tuned memory limits
├── kargo/
│   ├── install/
│   │   └── values.yaml                # Helm values for Kargo (Pi-tuned)
│   └── projects/
│       └── echo-server/
│           ├── project.yaml            # Kargo Project CRD
│           ├── warehouse.yaml          # Watches GHCR for new tags
│           ├── stage-dev.yaml          # Auto-promote from Warehouse
│           ├── stage-staging.yaml      # Auto-promote from dev
│           └── stage-prod.yaml         # Manual approval gate
├── environments/
│   ├── dev/
│   │   └── namespace.yaml              # Namespace + ResourceQuota
│   ├── staging/
│   │   └── namespace.yaml
│   └── prod/
│       └── namespace.yaml
└── argocd/
    └── apps/
        ├── root-app.yaml               # Unchanged (auto-discovers new apps)
        ├── cert-manager.yaml           # NEW: ArgoCD App for cert-manager
        ├── kargo.yaml                  # NEW: ArgoCD App for Kargo (multi-source)
        ├── environments.yaml           # NEW: ArgoCD App for namespace setup
        ├── echo-server-dev.yaml        # NEW: replaces echo-server.yaml
        ├── echo-server-staging.yaml    # NEW
        └── echo-server-prod.yaml       # NEW

charts/echo-server/
├── values.yaml                         # Unchanged (base defaults)
├── values-pi.yaml                      # Unchanged (Pi resource overrides)
├── values-dev.yaml                     # NEW: dev image tag + ingress host
├── values-staging.yaml                 # NEW: staging (Kargo updates tag)
└── values-prod.yaml                    # NEW: prod (Kargo updates tag)
```

## Kargo Concepts

| CRD           | Purpose                                                       | Count per app                     |
| ------------- | ------------------------------------------------------------- | --------------------------------- |
| **Project**   | Namespace + promotion policies for an app                     | 1                                 |
| **Warehouse** | Watches a source (registry, git, Helm repo) for new artifacts | 1                                 |
| **Freight**   | An immutable artifact reference (e.g., image tag 0.2.0)       | Created automatically             |
| **Stage**     | An environment. Defines how to promote Freight                | 1 per environment                 |
| **Promotion** | The act of moving Freight into a Stage                        | Created automatically or manually |

## Kargo CRD Definitions

### Project

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: echo-server
spec:
  promotionPolicies:
    - stage: dev
      autoPromotionEnabled: true # New images go straight to dev
    - stage: staging
      autoPromotionEnabled: true # Auto-promote after dev is healthy
    - stage: prod
      autoPromotionEnabled: false # Human must approve
```

Creates a `echo-server` namespace where all Kargo resources for this app live.

### Warehouse

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: echo-server
  namespace: echo-server
spec:
  subscriptions:
    - image:
        repoURL: ghcr.io/aroethe/homelab/echo-server
        semverConstraint: ">=0.1.0"
        discoveryLimit: 5
```

Polls GHCR every ~5 minutes. When it finds a new semver tag, it creates Freight.

**Implication**: Images must be tagged with semver (0.1.0, 0.2.0), not just `latest`.

### Stage: dev

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: dev
  namespace: echo-server
spec:
  requestedFreight:
    - origin:
        kind: Warehouse
        name: echo-server
      sources:
        direct: true # Accepts Freight directly from Warehouse
  promotionTemplate:
    spec:
      steps:
        - uses: git-clone
          config:
            repoURL: https://github.com/aroethe/homelab
            checkout:
              - branch: main
                path: ./src
        - uses: helm-update-image
          as: update-image
          config:
            path: ./src/charts/echo-server/values-dev.yaml
            images:
              - image: ghcr.io/aroethe/homelab/echo-server
                key: image.tag
                value: Tag
        - uses: git-commit
          config:
            path: ./src
            messageFromSteps:
              - update-image
        - uses: git-push
          config:
            path: ./src
        - uses: argocd-update
          config:
            apps:
              - name: echo-server-dev
                sources:
                  - repoURL: https://github.com/aroethe/homelab
                    desiredRevision: ${{ outputs.steps['git-push'].commit }}
```

Promotion steps: clone repo → update `values-dev.yaml` with new tag → commit →
push → tell ArgoCD to sync.

### Stage: staging

Same as dev, except:

```yaml
requestedFreight:
  - origin:
      kind: Warehouse
      name: echo-server
    sources:
      stages:
        - dev # Only Freight verified in dev
```

Updates `values-staging.yaml` and syncs `echo-server-staging` ArgoCD App.

### Stage: prod

Same pattern, except:

- `sources.stages: [staging]` — requires Freight verified in staging
- Updates `values-prod.yaml`, syncs `echo-server-prod`
- `autoPromotionEnabled: false` in Project — requires manual `kargo promote` or UI click

## ArgoCD Applications (per environment)

Each environment gets its own ArgoCD Application. Example for dev:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: echo-server-dev
  namespace: argocd
  labels:
    kargo.akuity.io/authorized-stage: echo-server:dev # Kargo authorization
spec:
  project: default
  source:
    repoURL: https://github.com/aroethe/homelab
    path: charts/echo-server
    targetRevision: main
    helm:
      valueFiles:
        - values.yaml
        - values-pi.yaml
        - values-dev.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

The `kargo.akuity.io/authorized-stage` label is required — it authorizes the
named Kargo Stage to trigger syncs on this Application.

## Kargo Installation (via ArgoCD)

Kargo publishes an OCI Helm chart. Use ArgoCD multi-source to combine the chart
with our values file:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kargo
  namespace: argocd
spec:
  project: default
  sources:
    - repoURL: oci://ghcr.io/akuity/kargo-charts/kargo
      targetRevision: "1.3.1"
      chart: kargo
      helm:
        valueFiles:
          - $values/platform/kargo/install/values.yaml
    - repoURL: https://github.com/aroethe/homelab
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: kargo
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Kargo Helm Values (Pi-tuned)

```yaml
# platform/kargo/install/values.yaml
api:
  adminAccount:
    enabled: true
    tokenSigningKey: "" # Generate with: openssl rand -base64 32
  resources:
    requests:
      cpu: 25m
      memory: 64Mi
    limits:
      memory: 128Mi

controller:
  resources:
    requests:
      cpu: 25m
      memory: 64Mi
    limits:
      memory: 256Mi

managementController:
  resources:
    requests:
      cpu: 10m
      memory: 32Mi
    limits:
      memory: 128Mi

webhooksServer:
  resources:
    requests:
      cpu: 10m
      memory: 32Mi
    limits:
      memory: 64Mi
```

## Per-Environment Helm Values

### values-dev.yaml

```yaml
image:
  tag: latest # Kargo overwrites this with semver tag
  pullPolicy: Always
ingress:
  host: echo-dev.homelab.local
resources:
  requests:
    cpu: 10m
    memory: 16Mi
  limits:
    cpu: 100m
    memory: 32Mi
```

### values-staging.yaml

```yaml
image:
  tag: "0.1.0" # Kargo overwrites this
ingress:
  host: echo-staging.homelab.local
resources:
  requests:
    cpu: 10m
    memory: 16Mi
  limits:
    cpu: 100m
    memory: 32Mi
```

### values-prod.yaml

```yaml
image:
  tag: "0.1.0" # Kargo overwrites this
ingress:
  host: echo.homelab.local
resources:
  requests:
    cpu: 10m
    memory: 16Mi
  limits:
    cpu: 100m
    memory: 32Mi
```

## Environment Namespaces with Resource Quotas

```yaml
# platform/environments/dev/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dev
  labels:
    environment: dev
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: env-quota
  namespace: dev
spec:
  hard:
    requests.memory: 512Mi
    limits.memory: 1Gi
    requests.cpu: 200m
    limits.cpu: "1"
```

Quotas prevent any single environment from starving the others:

| Environment | Memory Limit | CPU Limit |
| ----------- | ------------ | --------- |
| dev         | 1Gi          | 1 core    |
| staging     | 1Gi          | 1 core    |
| prod        | 1.5Gi        | 2 cores   |

## Manual Steps (not in git)

### 1. Git Credentials for Kargo

Kargo needs write access to the repo to commit tag updates. Apply this Secret
manually (never commit tokens to git):

```sh
kubectl create namespace echo-server  # Or let Kargo Project create it

kubectl -n echo-server create secret generic git-credentials \
  --from-literal=repoURL=https://github.com/aroethe/homelab \
  --from-literal=username=aroethe \
  --from-literal=password=<GITHUB_PAT>

kubectl -n echo-server label secret git-credentials \
  kargo.akuity.io/cred-type=git
```

The PAT needs `repo` scope (read/write access to repository contents).

### 2. Image Registry Credentials (if GHCR is private)

```sh
kubectl -n echo-server create secret generic image-credentials \
  --from-literal=repoURL=ghcr.io/aroethe/homelab/echo-server \
  --from-literal=username=aroethe \
  --from-literal=password=<GITHUB_PAT>

kubectl -n echo-server label secret image-credentials \
  kargo.akuity.io/cred-type=image
```

### 3. Kargo Admin Token Signing Key

Generate and set in Kargo values before install:

```sh
openssl rand -base64 32
# Paste into platform/kargo/install/values.yaml → api.adminAccount.tokenSigningKey
```

## End-to-End Promotion Workflow

```
1. Push code change to apps/echo-server/
          │
2. Build + push image (manual or CI)
   make echo-push-version VERSION=0.2.0
          │
3. Kargo Warehouse detects tag 0.2.0 → creates Freight
          │
4. Stage: dev (auto)
   ├── Clone repo
   ├── Update values-dev.yaml → image.tag: 0.2.0
   ├── Commit + push
   └── ArgoCD syncs echo-server-dev → ns: dev
          │
5. Stage: staging (auto, after dev healthy)
   ├── Clone repo
   ├── Update values-staging.yaml → image.tag: 0.2.0
   ├── Commit + push
   └── ArgoCD syncs echo-server-staging → ns: staging
          │
6. Stage: prod (manual approval required)
   ├── Human approves in Kargo UI / CLI
   ├── Clone repo
   ├── Update values-prod.yaml → image.tag: 0.2.0
   ├── Commit + push
   └── ArgoCD syncs echo-server-prod → ns: prod
```

## Installation Sequence

| Step | Command                                                    | Wait for                               |
| ---- | ---------------------------------------------------------- | -------------------------------------- |
| 1    | `kubectl apply -k platform/cert-manager/install/`          | All 3 cert-manager pods Running        |
| 2    | `kubectl apply -k platform/environments/` (or per-dir)     | Namespaces created                     |
| 3    | Push Kargo ArgoCD App → ArgoCD syncs                       | All 4 Kargo pods Running in `kargo` ns |
| 4    | Apply git + image credential Secrets manually              | Secrets exist                          |
| 5    | `kubectl apply -f platform/kargo/projects/echo-server/`    | Project + Warehouse + Stages created   |
| 6    | Replace `echo-server.yaml` with per-env apps, push to main | ArgoCD syncs 3 apps                    |
| 7    | `make echo-push-version VERSION=0.1.0`                     | Freight flows through pipeline         |

## Accessing the Kargo UI

Expose via NodePort (add to Kargo Helm values):

```yaml
api:
  service:
    type: NodePort
    nodePort: 30081
```

Then access at `http://<pi-ip>:30081`. Login with the admin token:

```sh
kargo login https://<pi-ip>:30081 --admin
```

## Known Considerations

**Git commit loops**: Kargo commits to the repo that ArgoCD watches. This is safe
because Kargo's `argocd-update` step pins ArgoCD to a specific commit SHA. ArgoCD
sees desired state = live state and does not re-sync.

**Semver discipline**: The Warehouse uses `semverConstraint`. Images must be tagged
with valid semver (0.1.0, 0.2.0), not `latest`. Update the Makefile to enforce this.

**Single-branch model**: All environments' values files live on `main`. Kargo's
sequential commits (dev, then staging, then prod) avoid conflicts. If two Freight
items race, Kargo retries automatically.

**Scaling out**: When you add a second app, create a new directory under
`platform/kargo/projects/<app-name>/` with its own Project, Warehouse, and Stages.
Add three ArgoCD Applications. The pattern is identical.
