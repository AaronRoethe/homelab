# Homelab

Kubernetes homelab running on a single Raspberry Pi (8GB), managed via GitOps
with ArgoCD and Kargo for progressive delivery.

## Architecture

```
                  ┌──────────────┐
                  │   GitHub     │
                  │  (this repo) │
                  └──────┬───────┘
                         │ git poll
              ┌──────────┼──────────┐
              ▼                     ▼
       ┌──────────┐         ┌──────────┐
       │  ArgoCD  │◀────────│  Kargo   │
       │ (sync)   │ trigger │(promote) │
       └──────┬───┘         └──────────┘
              │ deploy
    ┌─────────┼─────────┐
    ▼         ▼         ▼
  ns:dev   ns:staging  ns:prod
  (auto)   (auto)      (manual)
              │
       ┌──────▼───────┐
       │  k3s on Pi   │
       │  + Traefik   │
       └──────────────┘
```

## Stack

| Component         | Choice                                 | Why                                        |
| ----------------- | -------------------------------------- | ------------------------------------------ |
| OS                | Raspberry Pi OS Lite 64-bit (Bookworm) | Headless, minimal footprint                |
| Kubernetes        | k3s                                    | Built for ARM, ~500MB RAM                  |
| GitOps            | ArgoCD                                 | UI for learning, app-of-apps pattern       |
| Promotion         | Kargo                                  | Progressive delivery: dev → staging → prod |
| Ingress           | Traefik                                | Included in k3s, zero extra cost           |
| Charts            | Helm                                   | Flexible per-app configuration             |
| Container runtime | containerd                             | Default in k3s                             |

## Resource Budget (8GB Pi)

| Component            | RAM         |
| -------------------- | ----------- |
| OS + system          | ~400 MB     |
| k3s (server + agent) | ~500 MB     |
| ArgoCD (tuned)       | ~400 MB     |
| cert-manager         | ~200 MB     |
| Kargo (tuned)        | ~400 MB     |
| Traefik + CoreDNS    | ~80 MB      |
| Workloads (3 envs)   | ~100 MB     |
| **Remaining**        | **~5.9 GB** |

## Repo Structure

```
homelab/
├── apps/                          # Application source code + charts
│   └── echo-server/
│       ├── cmd/server/main.go     # App code
│       ├── Dockerfile
│       └── chart/                 # Base Helm chart (travels with the app)
│           ├── Chart.yaml
│           ├── values.yaml        # Defaults only
│           └── templates/
│
├── platform/                      # All infrastructure concerns
│   ├── argocd/
│   │   ├── install/               # Kustomize overlay on upstream manifests
│   │   └── apps/                  # App-of-apps: ArgoCD Application per workload
│   ├── cert-manager/
│   │   └── install/               # Kustomize + Pi resource limits
│   ├── kargo/
│   │   ├── install/               # Helm values for Kargo (Pi-tuned)
│   │   └── projects/              # Kargo Project, Warehouse, Stages per app
│   ├── environments/              # Namespace + ResourceQuota per env
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   └── overlays/                  # Per-env Helm value overrides
│       └── echo-server/
│           ├── values-pi.yaml
│           ├── values-dev.yaml
│           ├── values-staging.yaml
│           └── values-prod.yaml
│
├── pi-setup/                      # Bootstrap: Pi OS → running k3s
│
└── docs/                          # Plans and runbooks
    └── infra/
```

**Separation of concerns**: `apps/` contains application code and its base chart —
everything a dev team owns. `platform/` contains infrastructure: ArgoCD, Kargo,
environments, and deployment overlays — everything an ops team owns. `pi-setup/`
is hardware provisioning. Each can become its own repo later.

## Getting Started

### Phase 1: Bootstrap the Pi

1. Flash Raspberry Pi OS Lite 64-bit to SD card
2. Enable SSH, set hostname to `homelab`
3. SSH in and run the setup scripts:

```sh
git clone https://github.com/<you>/homelab.git
cd homelab/pi-setup
./install.sh
```

See [pi-setup/README.md](pi-setup/README.md) for details.

### Phase 2: Install Platform

From your local machine (with kubeconfig pointing at the Pi):

```sh
make argocd-install          # Install ArgoCD
make argocd-password         # Get initial admin password
make argocd-bootstrap        # Apply root app-of-apps
```

ArgoCD auto-discovers and syncs cert-manager, Kargo, environments, and all
app deployments from the `platform/argocd/apps/` directory.

### Phase 3: Configure Kargo

```sh
# Create git credentials (Kargo needs repo write access for tag promotions)
kubectl create namespace echo-server
kubectl -n echo-server create secret generic git-credentials \
  --from-literal=repoURL=https://github.com/<you>/homelab \
  --from-literal=username=<you> \
  --from-literal=password=<GITHUB_PAT>
kubectl -n echo-server label secret git-credentials kargo.akuity.io/cred-type=git

# Apply Kargo project and stages
make kargo-projects
```

### Phase 4: Deploy

```sh
make echo-release VERSION=0.1.0    # Build + push semver-tagged ARM64 image
```

Kargo detects the new tag and promotes automatically:
`dev (auto) → staging (auto) → prod (manual approval in Kargo UI)`

## Adding a New Application

1. Create app code + base chart in `apps/<name>/` with `apps/<name>/chart/`
2. Create env overlays in `platform/overlays/<name>/`
3. Add per-env ArgoCD Applications in `platform/argocd/apps/`
4. Add Kargo Project + Warehouse + Stages in `platform/kargo/projects/<name>/`
5. Push to `main` — Kargo and ArgoCD handle the rest

## Docs

- [Multi-Environment Deployment Plan](docs/infra/multi-environment-deployment.md)

## Future Plans

- [ ] CI pipeline (GitHub Actions for ARM64 image builds)
- [ ] Lightweight monitoring (VictoriaMetrics)
- [ ] Local DNS with Pi-hole (`*.homelab.local`)
- [ ] TLS via cert-manager with self-signed CA
- [ ] Persistent storage with Longhorn
