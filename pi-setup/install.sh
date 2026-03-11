#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Homelab Pi Setup ==="
echo "This will configure the system, install k3s, and verify the cluster."
echo ""

read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "--- Step 1: System Preparation ---"
bash "$SCRIPT_DIR/01-system-prep.sh"

echo ""
echo "--- Step 2: k3s Installation ---"
bash "$SCRIPT_DIR/02-k3s-install.sh"

echo ""
echo "--- Step 3: Post-Install Verification ---"
bash "$SCRIPT_DIR/03-post-install.sh"

echo ""
echo "=== Setup Complete ==="
