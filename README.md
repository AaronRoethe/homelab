# Homelab

Kubernetes homelab running on a single Raspberry Pi (8GB), managed via GitOps with ArgoCD.

## Architecture

```
                  ┌──────────────┐
                  │   GitHub     │
                  │  (this repo) │
                  └──────┬───────┘
                         │ git poll
                  ┌──────▼───────┐
                  │   ArgoCD     │
                  │  (app-of-apps)│
                  └──────┬───────┘
                         │ sync
              ┌──────────┼──────────┐
              ▼          ▼          ▼
         ┌─────────┐ ┌────────┐ ┌────────┐
         │ echo-   │ │ app-2  │ │ app-N  │
         │ server  │ │(future)│ │(future)│
         └─────────┘ └────────┘ └────────┘
                         │
                  ┌──────▼───────┐
                  │  k3s on Pi   │
                  │  + Traefik   │
                  └──────────────┘
```

## Stack

| Component         | Choice                                 | Why                                  |
| ----------------- | -------------------------------------- | ------------------------------------ |
| OS                | Raspberry Pi OS Lite 64-bit (Bookworm) | Headless, minimal footprint          |
| Kubernetes        | k3s                                    | Built for ARM, ~500MB RAM            |
| GitOps            | ArgoCD                                 | UI for learning, app-of-apps pattern |
| Ingress           | Traefik                                | Included in k3s, zero extra cost     |
| Charts            | Helm                                   | Flexible per-app configuration       |
| Container runtime | containerd                             | Default in k3s                       |

## Resource Budget (8GB Pi)

| Component            | RAM               |
| -------------------- | ----------------- |
| OS + system          | ~400 MB           |
| k3s (server + agent) | ~500 MB           |
| ArgoCD (tuned)       | ~400 MB           |
| Traefik + CoreDNS    | ~80 MB            |
| Your workloads       | ~5.5 GB available |

## Repo Structure

```
homelab/
├── pi-setup/         # Bootstrap: Pi OS → running k3s cluster
├── platform/         # Cluster infrastructure (ArgoCD, future platform services)
│   └── argocd/
│       ├── install/  # Kustomize overlay on upstream ArgoCD manifests
│       └── apps/     # App-of-apps: one Application YAML per workload
├── apps/             # Application source code
│   └── echo-server/  # Starter Go service
├── charts/           # Helm charts (one per app)
│   └── echo-server/
└── docs/             # ADRs and runbooks
```

This is a monorepo. Each top-level directory is a self-contained concern that can be
split into its own repo later. The only coupling is ArgoCD Application manifests
pointing at paths — update `repoURL` and `path` when you split.

## Getting Started

### Phase 1: Bootstrap the Pi

1. Flash Raspberry Pi OS Lite 64-bit to SD card
2. Enable SSH, set hostname to `homelab`
3. SSH in and run the setup scripts:

```sh
# On the Pi
curl -sfL https://raw.githubusercontent.com/<you>/homelab/main/pi-setup/install.sh | bash
```

Or clone the repo and run locally:

```sh
git clone https://github.com/<you>/homelab.git
cd homelab/pi-setup
./install.sh
```

See [pi-setup/README.md](pi-setup/README.md) for details.

### Phase 2: Install ArgoCD

From your local machine (with kubeconfig pointing at the Pi):

```sh
kubectl apply -k platform/argocd/install/
```

Wait for ArgoCD to be ready, then get the initial admin password:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

Access the UI at `http://<pi-ip>:30080`.

### Phase 3: Deploy the App-of-Apps

```sh
kubectl apply -f platform/argocd/apps/root-app.yaml
```

ArgoCD now manages itself. Push changes to `main` and ArgoCD syncs automatically.

### Phase 4: Build and Deploy the Echo Server

```sh
cd apps/echo-server
make build-push   # builds ARM64 image, pushes to registry
```

ArgoCD picks up the chart and deploys it. Verify:

```sh
curl http://echo.homelab.local/
```

## Adding a New Application

1. Create app source code in `apps/<name>/`
2. Create a Helm chart in `charts/<name>/`
3. Add an ArgoCD Application manifest in `platform/argocd/apps/<name>.yaml`
4. Push to `main` — ArgoCD deploys it

## Future Plans

- [ ] CI pipeline (GitHub Actions for ARM64 image builds)
- [ ] Lightweight monitoring (VictoriaMetrics)
- [ ] Local DNS with Pi-hole (`*.homelab.local`)
- [ ] TLS via cert-manager with self-signed CA
- [ ] Persistent storage with Longhorn
