#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="homelab"
REGISTRY_NAME="registry.homelab.local"
REGISTRY_PORT=30500
REGISTRY_HOST="k3d-${REGISTRY_NAME}:${REGISTRY_PORT}"

usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  up        One-click: create cluster, bootstrap, build and deploy apps"
    echo "  create    Create local k3d cluster with registry"
    echo "  delete    Delete the cluster and registry"
    echo "  status    Show cluster status"
    echo "  bootstrap Install ArgoCD and apply root app"
    echo "  deploy    Build and push all app images to local registry"
    echo ""
}

check_deps() {
    local missing=()
    for cmd in docker k3d kubectl helm go; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Missing dependencies: ${missing[*]}"
        echo ""
        echo "Install with:"
        echo "  brew install k3d kubectl helm go"
        echo "  # Docker Desktop or OrbStack required for Docker"
        exit 1
    fi
}

ensure_hosts_entry() {
    if ! grep -q "$REGISTRY_HOST" /etc/hosts 2>/dev/null; then
        echo ""
        echo "Adding $REGISTRY_HOST to /etc/hosts (requires sudo)..."
        echo "127.0.0.1 $REGISTRY_HOST" | sudo tee -a /etc/hosts > /dev/null
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
        --registry-use "${REGISTRY_HOST}" \
        --port "80:80@loadbalancer" \
        --port "443:443@loadbalancer" \
        --port "30080:30080@server:0" \
        --port "30081:30081@server:0" \
        --k3s-arg "--disable=local-storage@server:0"

    echo ""
    echo "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready node --all --timeout=60s

    ensure_hosts_entry

    echo ""
    echo "=== Cluster Ready ==="
    kubectl get nodes
    echo ""
    echo "Registry: ${REGISTRY_HOST}"
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
    echo "=== ArgoCD Apps ==="
    kubectl get apps -n argocd 2>/dev/null || echo "ArgoCD not installed"
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
    echo "Waiting for ArgoCD to sync apps..."
    sleep 15

    echo ""
    ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' | base64 -d)

    echo "=== Bootstrap Complete ==="
    echo ""
    echo "ArgoCD UI:  http://localhost:30080"
    echo "  Username: admin"
    echo "  Password: $ARGOCD_PASS"
    echo ""
    echo "Kargo UI:   http://localhost:30081"
    echo "  Username: admin"
    echo "  Password: admin"
    echo ""
    kubectl get apps -n argocd
}

deploy_apps() {
    echo "=== Building and pushing app images ==="

    echo ""
    echo "--- echo-server ---"
    cd apps/echo-server
    go test -race -count=1 ./...
    cd ../..
    docker build -f apps/echo-server/Dockerfile -t "${REGISTRY_HOST}/echo-server:0.1.0" .
    docker push "${REGISTRY_HOST}/echo-server:0.1.0"

    echo ""
    echo "--- traffic-gen ---"
    cd apps/traffic-gen
    go vet ./...
    cd ../..
    docker build -f apps/traffic-gen/Dockerfile -t "${REGISTRY_HOST}/traffic-gen:0.1.0" .
    docker push "${REGISTRY_HOST}/traffic-gen:0.1.0"

    echo ""
    echo "=== Images pushed to ${REGISTRY_HOST} ==="
    echo ""
    echo "Waiting for ArgoCD to sync deployments..."
    sleep 10

    # Restart deployments to pick up new images
    for ns in dev staging prod; do
        kubectl rollout restart deployment/echo-server -n "$ns" 2>/dev/null || true
    done

    sleep 15
    echo ""
    kubectl get pods -A -l app.kubernetes.io/name=echo-server
}

up_cluster() {
    echo "=== One-Click Setup ==="
    echo ""

    # Step 1: Create cluster
    if k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
        echo "Cluster exists, deleting first..."
        delete_cluster
        echo ""
    fi
    create_cluster

    echo ""

    # Step 2: Bootstrap ArgoCD
    bootstrap_cluster

    echo ""

    # Step 3: Build and deploy apps
    deploy_apps

    echo ""
    echo "=== All Done ==="
    echo ""
    echo "ArgoCD:       http://localhost:30080  (admin / see above)"
    echo "Kargo:        http://localhost:30081  (admin / admin)"
    echo "echo-server:  Running in dev, staging, prod namespaces"
    echo ""
    echo "Status:  make cluster-status"
    echo "Tear down: make cluster-delete"
}

case "${1:-}" in
    up)        up_cluster ;;
    create)    create_cluster ;;
    delete)    delete_cluster ;;
    status)    status_cluster ;;
    bootstrap) bootstrap_cluster ;;
    deploy)    deploy_apps ;;
    *)         usage ;;
esac
