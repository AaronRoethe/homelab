.PHONY: help pi-setup argocd-install argocd-bootstrap echo-build echo-push

REGISTRY ?= ghcr.io/aroethe/homelab
PI_HOST ?= homelab.local

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

## --- Pi Setup ---

pi-setup: ## Run full Pi bootstrap (SSH into Pi first)
	cd pi-setup && ./install.sh

## --- Platform ---

argocd-install: ## Install ArgoCD on the cluster
	kubectl apply -k platform/argocd/install/

argocd-password: ## Get ArgoCD initial admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo

argocd-bootstrap: ## Apply the root app-of-apps
	kubectl apply -f platform/argocd/apps/root-app.yaml

## --- Apps ---

echo-build: ## Build echo-server container (ARM64)
	cd apps/echo-server && docker buildx build --platform linux/arm64 -t $(REGISTRY)/echo-server:latest .

echo-push: ## Build and push echo-server container (ARM64)
	cd apps/echo-server && docker buildx build --platform linux/arm64 -t $(REGISTRY)/echo-server:latest --push .
