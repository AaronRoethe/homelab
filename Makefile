.PHONY: help cluster-up cluster-create cluster-delete cluster-bootstrap cluster-deploy cluster-status pi-setup argocd-install argocd-password argocd-bootstrap kargo-projects kargo-verification echo-build echo-push echo-release echo-test validate-chart smoke-dev smoke-staging smoke-prod smoke-all

REGISTRY ?= k3d-registry.homelab.local:30500
PI_HOST ?= homelab.local
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "0.0.0")

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

## --- Local Cluster ---

cluster-up: ## One-click: create cluster, bootstrap, build and deploy everything
	./scripts/local-cluster.sh up

cluster-create: ## Create local k3d cluster with registry
	./scripts/local-cluster.sh create

cluster-delete: ## Delete local k3d cluster
	./scripts/local-cluster.sh delete

cluster-bootstrap: ## Install ArgoCD and apply root app
	./scripts/local-cluster.sh bootstrap

cluster-deploy: ## Build and push all app images to local registry
	./scripts/local-cluster.sh deploy

cluster-status: ## Show local cluster status
	./scripts/local-cluster.sh status

## --- Pi Setup ---

pi-setup: ## Run full Pi bootstrap (SSH into Pi first)
	cd pi-setup && ./install.sh

## --- Platform ---

argocd-install: ## Install ArgoCD on the cluster
	kubectl apply -k platform/infra/argocd/

argocd-password: ## Get ArgoCD initial admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo

argocd-bootstrap: ## Apply the root app-of-apps
	kubectl apply -f platform/apps/root-app.yaml

kargo-projects: ## Apply Kargo project, warehouse, and stages for echo-server
	kubectl apply -f platform/kargo/projects/echo-server/project.yaml
	@echo "Waiting for project namespace..."
	@sleep 5
	kubectl apply -f platform/kargo/projects/echo-server/

kargo-verification: ## Apply Kargo verification AnalysisTemplates
	kubectl apply -f tests/kargo/

## --- Apps ---

echo-build: ## Build echo-server container
	docker build -t $(REGISTRY)/echo-server:latest -f apps/echo-server/Dockerfile .

echo-push: echo-build ## Build and push echo-server container
	docker push $(REGISTRY)/echo-server:latest

echo-test: ## Run echo-server unit tests
	cd apps/echo-server && go test -race -count=1 ./...

echo-release: echo-test ## Build and push with semver tag (VERSION=0.1.0)
	@echo "Building and pushing echo-server:$(VERSION)"
	docker build -f apps/echo-server/Dockerfile \
		-t $(REGISTRY)/echo-server:$(VERSION) \
		-t $(REGISTRY)/echo-server:latest .
	docker push $(REGISTRY)/echo-server:$(VERSION)
	docker push $(REGISTRY)/echo-server:latest

## --- Validation ---

validate-chart: ## Lint and template echo-server Helm chart
	helm lint apps/echo-server/chart/
	helm template echo-server apps/echo-server/chart/ --namespace dev > /dev/null
	@echo "All chart validations passed"

## --- Smoke Tests ---

smoke-dev: ## Smoke test echo-server in dev
	@bash tests/smoke-test.sh dev

smoke-staging: ## Smoke test echo-server in staging
	@bash tests/smoke-test.sh staging

smoke-prod: ## Smoke test echo-server in prod
	@bash tests/smoke-test.sh prod

smoke-all: smoke-dev smoke-staging smoke-prod ## Smoke test all environments
