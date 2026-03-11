REGISTRY ?= ghcr.io/aroethe/homelab
IMAGE := $(REGISTRY)/echo-server
E2E_IMAGE := $(REGISTRY)/echo-server-e2e
TAG ?= latest

.PHONY: build run test vet docker-build docker-push e2e-build e2e-push

build: ## Build the binary locally
	go build -o echo-server ./cmd/server

run: build ## Run locally
	./echo-server

test: ## Run unit tests with race detection
	go test -race -count=1 ./...

vet: ## Run go vet
	go vet ./...

docker-build: ## Build container image for ARM64
	docker buildx build --platform linux/arm64 -t $(IMAGE):$(TAG) .

docker-push: ## Build and push container image for ARM64
	docker buildx build --platform linux/arm64 -t $(IMAGE):$(TAG) --push .

e2e-build: ## Build E2E test container (ARM64)
	docker buildx build --platform linux/arm64 -t $(E2E_IMAGE):latest -f e2e/Dockerfile .

e2e-push: ## Build and push E2E test container (ARM64)
	docker buildx build --platform linux/arm64 -t $(E2E_IMAGE):latest -f e2e/Dockerfile --push .
