#!/usr/bin/env bash
set -euo pipefail

ENV="${1:-}"
if [ -z "$ENV" ]; then
    echo "Usage: smoke-test.sh <dev|staging|prod>"
    exit 1
fi

case "$ENV" in
    dev)     HOST="echo-dev.homelab.local" ;;
    staging) HOST="echo-staging.homelab.local" ;;
    prod)    HOST="echo.homelab.local" ;;
    *)       echo "Unknown environment: $ENV"; exit 1 ;;
esac

PASS=0
FAIL=0

check() {
    local name="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        echo "  PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $name"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Smoke test: $ENV ==="
echo ""

echo "--- Rollout status ---"
check "deployment ready" kubectl rollout status "deployment/echo-server" -n "$ENV" --timeout=60s

echo ""
echo "--- Health check ---"
HEALTH_RESP=$(curl -sf --max-time 5 "http://$HOST/healthz" 2>/dev/null || echo "")
check "/healthz returns 200" [ -n "$HEALTH_RESP" ]
check "/healthz status ok" echo "$HEALTH_RESP" | grep -q '"status":"ok"'

echo ""
echo "--- Functional check ---"
ECHO_RESP=$(curl -sf --max-time 5 "http://$HOST/" 2>/dev/null || echo "")
check "/ returns response" [ -n "$ECHO_RESP" ]
check "/ has hostname" echo "$ECHO_RESP" | grep -q '"hostname"'
check "/ has arch" echo "$ECHO_RESP" | grep -q '"arch"'
check "/ has timestamp" echo "$ECHO_RESP" | grep -q '"timestamp"'

echo ""
echo "--- Image tag ---"
IMAGE=$(kubectl get deployment echo-server -n "$ENV" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "unknown")
echo "  Running image: $IMAGE"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
