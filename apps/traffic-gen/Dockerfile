FROM golang:1.22-alpine AS build
WORKDIR /src
COPY apps/pkg/cfg/ apps/pkg/cfg/
COPY apps/traffic-gen/ apps/traffic-gen/
RUN cd apps/traffic-gen && go mod download 2>/dev/null || true
RUN cd apps/traffic-gen && CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /traffic-gen ./cmd/traffic-gen

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=build /traffic-gen /app/traffic-gen
ENTRYPOINT ["/app/traffic-gen"]
