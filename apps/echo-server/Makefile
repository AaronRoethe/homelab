REGISTRY ?= ghcr.io/aroethe/homelab
IMAGE := $(REGISTRY)/echo-server
TAG ?= latest

.PHONY: build run test docker-build docker-push

build: ## Build the binary locally
	go build -o echo-server ./cmd/server

run: build ## Run locally
	./echo-server

test: ## Run tests
	go test ./...

docker-build: ## Build container image for ARM64
	docker buildx build --platform linux/arm64 -t $(IMAGE):$(TAG) .

docker-push: ## Build and push container image for ARM64
	docker buildx build --platform linux/arm64 -t $(IMAGE):$(TAG) --push .
