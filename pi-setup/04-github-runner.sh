#!/usr/bin/env bash
set -euo pipefail

RUNNER_VERSION="2.321.0"
RUNNER_ARCH="arm64"
RUNNER_USER="github-runner"
RUNNER_DIR="/opt/actions-runner"
REPO_URL="https://github.com/AaronRoethe/homelab"

echo "=== GitHub Actions Self-Hosted Runner Setup ==="
echo ""

# --- Docker ---
echo "--- Installing Docker CE ---"
if command -v docker &>/dev/null; then
    echo "Docker already installed: $(docker --version)"
else
    curl -fsSL https://get.docker.com | sh
    echo "Docker installed."
fi

# --- Create runner user ---
echo ""
echo "--- Setting up runner user ---"
if id "$RUNNER_USER" &>/dev/null; then
    echo "User $RUNNER_USER already exists."
else
    sudo useradd -m -s /bin/bash "$RUNNER_USER"
    echo "Created user: $RUNNER_USER"
fi

sudo usermod -aG docker "$RUNNER_USER"
echo "Added $RUNNER_USER to docker group."

# --- Configure Docker for insecure local registry ---
echo ""
echo "--- Configuring Docker for local registry ---"
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "insecure-registries": ["registry.homelab.local:30500"]
}
EOF
sudo systemctl restart docker

# --- Install runner binary ---
echo ""
echo "--- Installing GitHub Actions runner ---"
sudo mkdir -p "$RUNNER_DIR"
sudo chown "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"

cd "$RUNNER_DIR"
RUNNER_TAR="actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
if [ ! -f "$RUNNER_TAR" ]; then
    sudo -u "$RUNNER_USER" curl -sL \
        "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_TAR}" \
        -o "$RUNNER_TAR"
    sudo -u "$RUNNER_USER" tar xzf "$RUNNER_TAR"
fi

# --- Configure runner ---
echo ""
echo "--- Runner Configuration ---"
echo ""
echo "You need a registration token from GitHub:"
echo "  1. Go to ${REPO_URL}/settings/actions/runners/new"
echo "  2. Copy the token shown in the 'Configure' section"
echo ""

read -p "Paste your registration token: " TOKEN

sudo -u "$RUNNER_USER" ./config.sh \
    --url "$REPO_URL" \
    --token "$TOKEN" \
    --labels "arm64,pi,homelab" \
    --name "pi-runner" \
    --work "_work" \
    --unattended \
    --replace

# --- Install as systemd service ---
echo ""
echo "--- Installing systemd service ---"
sudo ./svc.sh install "$RUNNER_USER"
sudo ./svc.sh start

echo ""
echo "=== Runner Setup Complete ==="
echo ""
echo "Status: sudo ./svc.sh status"
echo "Logs:   sudo journalctl -u actions.runner.*.service -f"
echo ""
echo "The runner is registered with labels: arm64, pi, homelab"
echo "Workflows can target it with: runs-on: [self-hosted, arm64]"
