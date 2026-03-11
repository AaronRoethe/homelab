.PHONY: help pi-setup argocd-install argocd-bootstrap cert-manager-install kargo-projects kargo-verification echo-build echo-push echo-release echo-test echo-e2e-build echo-e2e-push validate-chart smoke-dev smoke-staging smoke-prod smoke-all

REGISTRY ?= registry.homelab.local:30500
PI_HOST ?= homelab.local
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "0.0.0")

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

## --- Local Cluster ---

cluster-create: ## Create local k3d cluster with registry
	./scripts/local-cluster.sh create

cluster-delete: ## Delete local k3d cluster
	./scripts/local-cluster.sh delete

cluster-bootstrap: ## Install ArgoCD and apply root app
	./scripts/local-cluster.sh bootstrap

cluster-status: ## Show local cluster status
	./scripts/local-cluster.sh status

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

cert-manager-install: ## Install cert-manager (Kargo prerequisite)
	kubectl apply -k platform/cert-manager/install/

kargo-projects: ## Apply Kargo project, warehouse, and stages for echo-server
	kubectl apply -f platform/kargo/projects/echo-server/project.yaml
	@echo "Waiting for project namespace..."
	@sleep 5
	kubectl apply -f platform/kargo/projects/echo-server/

## --- Apps ---

echo-build: ## Build echo-server container (ARM64)
	cd apps/echo-server && docker buildx build --platform linux/arm64 -t $(REGISTRY)/echo-server:latest .

echo-push: ## Build and push echo-server container (ARM64, latest)
	cd apps/echo-server && docker buildx build --platform linux/arm64 -t $(REGISTRY)/echo-server:latest --push .

echo-test: ## Run echo-server unit tests
	cd apps/echo-server && go test -race -count=1 ./...

echo-release: echo-test ## Build and push with semver tag (VERSION=0.1.0)
	@echo "Building and pushing echo-server:$(VERSION)"
	cd apps/echo-server && docker buildx build --platform linux/arm64 \
		-t $(REGISTRY)/echo-server:$(VERSION) \
		-t $(REGISTRY)/echo-server:latest \
		--push .

echo-e2e-build: ## Build E2E test container (ARM64)
	cd apps/echo-server && docker buildx build --platform linux/arm64 \
		-t $(REGISTRY)/echo-server-e2e:latest -f e2e/Dockerfile .

echo-e2e-push: ## Build and push E2E test container (ARM64)
	cd apps/echo-server && docker buildx build --platform linux/arm64 \
		-t $(REGISTRY)/echo-server-e2e:latest -f e2e/Dockerfile --push .

## --- Validation ---

validate-chart: ## Lint and template echo-server Helm chart
	helm lint apps/echo-server/chart/ -f platform/overlays/echo-server/values-pi.yaml -f platform/overlays/echo-server/values-dev.yaml
	helm lint apps/echo-server/chart/ -f platform/overlays/echo-server/values-pi.yaml -f platform/overlays/echo-server/values-staging.yaml
	helm lint apps/echo-server/chart/ -f platform/overlays/echo-server/values-pi.yaml -f platform/overlays/echo-server/values-prod.yaml
	@echo "--- Template rendering ---"
	helm template echo-server apps/echo-server/chart/ -f platform/overlays/echo-server/values-pi.yaml -f platform/overlays/echo-server/values-dev.yaml --namespace dev > /dev/null
	helm template echo-server apps/echo-server/chart/ -f platform/overlays/echo-server/values-pi.yaml -f platform/overlays/echo-server/values-staging.yaml --namespace staging > /dev/null
	helm template echo-server apps/echo-server/chart/ -f platform/overlays/echo-server/values-pi.yaml -f platform/overlays/echo-server/values-prod.yaml --namespace prod > /dev/null
	@echo "All chart validations passed"

kargo-verification: ## Apply Kargo verification AnalysisTemplates
	kubectl apply -f tests/kargo/

## --- Smoke Tests ---

smoke-dev: ## Smoke test echo-server in dev
	@bash tests/smoke-test.sh dev

smoke-staging: ## Smoke test echo-server in staging
	@bash tests/smoke-test.sh staging

smoke-prod: ## Smoke test echo-server in prod
	@bash tests/smoke-test.sh prod

smoke-all: smoke-dev smoke-staging smoke-prod ## Smoke test all environments
