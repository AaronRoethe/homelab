FROM golang:1.22-alpine AS build
WORKDIR /src
COPY apps/pkg/cfg/ apps/pkg/cfg/
COPY apps/echo-server/ apps/echo-server/
RUN cd apps/echo-server && go mod download 2>/dev/null || true
RUN cd apps/echo-server && CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /echo-server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=build /echo-server /app/echo-server
EXPOSE 8080
ENTRYPOINT ["/app/echo-server"]
