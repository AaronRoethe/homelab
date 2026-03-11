#!/usr/bin/env bash
set -euo pipefail

echo "Updating packages..."
sudo apt-get update && sudo apt-get upgrade -y

echo "Installing required packages..."
sudo apt-get install -y curl open-iscsi nfs-common

echo "Disabling swap (required for Kubernetes)..."
sudo dphys-swapfile swapoff || true
sudo systemctl disable dphys-swapfile || true

echo "Enabling cgroups..."
CMDLINE="/boot/firmware/cmdline.txt"
if [ -f "$CMDLINE" ]; then
    if ! grep -q "cgroup_memory=1" "$CMDLINE"; then
        sudo sed -i 's/$/ cgroup_memory=1 cgroup_enable=memory/' "$CMDLINE"
        echo "cgroups enabled — reboot required after setup completes."
        NEEDS_REBOOT=1
    else
        echo "cgroups already enabled."
    fi
else
    echo "WARNING: $CMDLINE not found. You may need to enable cgroups manually."
fi

echo "Applying sysctl tuning..."
sudo tee /etc/sysctl.d/99-homelab.conf > /dev/null <<EOF
# Increase inotify watches (ArgoCD needs this)
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512

# Network tuning
net.core.somaxconn = 4096
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

echo "Setting hostname..."
CURRENT_HOSTNAME=$(hostname)
if [ "$CURRENT_HOSTNAME" != "homelab" ]; then
    sudo hostnamectl set-hostname homelab
    echo "Hostname set to 'homelab' (was '$CURRENT_HOSTNAME')."
fi

echo "System preparation complete."
if [ "${NEEDS_REBOOT:-0}" = "1" ]; then
    echo ""
    echo "NOTE: A reboot is needed for cgroup changes. The install script will"
    echo "continue with k3s installation, but you should reboot after completion."
fi
