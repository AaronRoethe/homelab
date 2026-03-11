FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod go.sum* ./
RUN go mod download 2>/dev/null || true
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /traffic-gen ./cmd/traffic-gen

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /traffic-gen /traffic-gen
ENTRYPOINT ["/traffic-gen"]
