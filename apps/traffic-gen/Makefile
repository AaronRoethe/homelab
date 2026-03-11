REGISTRY ?= registry.homelab.local:30500
IMAGE := $(REGISTRY)/traffic-gen
TAG ?= latest

.PHONY: build run test docker-build docker-push

build: ## Build the binary locally
	go build -o bin/traffic-gen ./cmd/traffic-gen

run: build ## Run locally against a target
	TARGET_URL=http://localhost:8080 REQUESTS=10 CONCURRENCY=2 DELAY_MS=200 ./bin/traffic-gen

test: ## Run tests
	go test ./...

vet: ## Run go vet
	go vet ./...

docker-build: ## Build container image for ARM64
	docker buildx build --platform linux/arm64 -t $(IMAGE):$(TAG) .

docker-push: ## Build and push container image for ARM64
	docker buildx build --platform linux/arm64 -t $(IMAGE):$(TAG) --push .
