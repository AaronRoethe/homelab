#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="homelab"
REGISTRY_NAME="registry.homelab.local"
REGISTRY_PORT=30500

usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  create    Create local k3d cluster with registry"
    echo "  delete    Delete the cluster and registry"
    echo "  status    Show cluster status"
    echo "  bootstrap Install ArgoCD and apply root app"
    echo ""
}

check_deps() {
    local missing=()
    for cmd in docker k3d kubectl helm; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Missing dependencies: ${missing[*]}"
        echo ""
        echo "Install with:"
        echo "  brew install k3d kubectl helm"
        echo "  # Docker Desktop or OrbStack required for Docker"
        exit 1
    fi
}

create_cluster() {
    check_deps

    if k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
        echo "Cluster '$CLUSTER_NAME' already exists."
        echo "Run '$0 delete' first to recreate."
        exit 1
    fi

    echo "=== Creating k3d cluster: $CLUSTER_NAME ==="

    # Create a local registry that k3d connects to the cluster network
    if ! k3d registry list 2>/dev/null | grep -q "$REGISTRY_NAME"; then
        echo "Creating local registry..."
        k3d registry create "$REGISTRY_NAME" --port "$REGISTRY_PORT"
    fi

    echo "Creating cluster..."
    k3d cluster create "$CLUSTER_NAME" \
        --registry-use "k3d-${REGISTRY_NAME}:${REGISTRY_PORT}" \
        --port "80:80@loadbalancer" \
        --port "443:443@loadbalancer" \
        --port "30080:30080@server:0" \
        --port "30081:30081@server:0" \
        --k3s-arg "--disable=local-storage@server:0"

    echo ""
    echo "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready node --all --timeout=60s

    echo ""
    echo "=== Cluster Ready ==="
    kubectl get nodes
    echo ""
    echo "Registry: localhost:${REGISTRY_PORT}"
    echo "ArgoCD:   http://localhost:30080 (after bootstrap)"
    echo "Kargo:    http://localhost:30081 (after bootstrap)"
    echo ""
    echo "Next: $0 bootstrap"
}

delete_cluster() {
    echo "Deleting cluster '$CLUSTER_NAME'..."
    k3d cluster delete "$CLUSTER_NAME" 2>/dev/null || true
    echo "Deleting registry '$REGISTRY_NAME'..."
    k3d registry delete "k3d-${REGISTRY_NAME}" 2>/dev/null || true
    echo "Done."
}

status_cluster() {
    echo "=== Cluster ==="
    k3d cluster list 2>/dev/null || echo "No clusters found"
    echo ""
    echo "=== Registry ==="
    k3d registry list 2>/dev/null || echo "No registries found"
    echo ""
    echo "=== Nodes ==="
    kubectl get nodes 2>/dev/null || echo "Cannot connect to cluster"
    echo ""
    echo "=== Pods (all namespaces) ==="
    kubectl get pods -A 2>/dev/null || true
}

bootstrap_cluster() {
    check_deps

    if ! kubectl get nodes &>/dev/null; then
        echo "No cluster running. Run '$0 create' first."
        exit 1
    fi

    echo "=== Installing ArgoCD ==="
    kubectl apply -k platform/infra/argocd/

    echo ""
    echo "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available deployment/argocd-server \
        -n argocd --timeout=180s

    echo ""
    echo "=== Applying root app-of-apps ==="
    kubectl apply -f platform/apps/root-app.yaml

    echo ""
    ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' | base64 -d)

    echo "=== Bootstrap Complete ==="
    echo ""
    echo "ArgoCD UI:  http://localhost:30080"
    echo "  Username: admin"
    echo "  Password: $ARGOCD_PASS"
    echo ""
    echo "ArgoCD will now sync all apps from platform/apps/"
    echo "Watch progress: kubectl get apps -n argocd"
}

case "${1:-}" in
    create)    create_cluster ;;
    delete)    delete_cluster ;;
    status)    status_cluster ;;
    bootstrap) bootstrap_cluster ;;
    *)         usage ;;
esac
