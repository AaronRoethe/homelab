FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod go.sum* ./
RUN go mod download 2>/dev/null || true
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go test -tags e2e -c -o /e2e-tests ./e2e/

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /e2e-tests /e2e-tests
ENTRYPOINT ["/e2e-tests", "-test.v"]
