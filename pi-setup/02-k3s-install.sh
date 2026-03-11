#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K3S_CONFIG_DIR="/etc/rancher/k3s"

echo "Creating k3s config directory..."
sudo mkdir -p "$K3S_CONFIG_DIR"

echo "Installing k3s server config..."
sudo cp "$SCRIPT_DIR/config/k3s-config.yaml" "$K3S_CONFIG_DIR/config.yaml"

echo "Installing k3s..."
curl -sfL https://get.k3s.io | sh -

echo "Waiting for k3s to be ready..."
ATTEMPTS=0
MAX_ATTEMPTS=30
until sudo k3s kubectl get nodes &>/dev/null; do
    ATTEMPTS=$((ATTEMPTS + 1))
    if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]; then
        echo "ERROR: k3s did not become ready in time."
        echo "Check logs: sudo journalctl -u k3s -f"
        exit 1
    fi
    echo "  Waiting for k3s... ($ATTEMPTS/$MAX_ATTEMPTS)"
    sleep 5
done

echo "k3s installed and running."
