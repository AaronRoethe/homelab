#!/usr/bin/env bash
set -euo pipefail

PI_IP=$(hostname -I | awk '{print $1}')

echo "Verifying cluster..."
sudo k3s kubectl get nodes
echo ""

echo "Labeling node..."
NODE_NAME=$(sudo k3s kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
sudo k3s kubectl label node "$NODE_NAME" node-role.kubernetes.io/worker=true --overwrite

echo ""
echo "Cluster is ready. Node info:"
sudo k3s kubectl get nodes -o wide
echo ""

echo "=== Kubeconfig Setup ==="
echo ""
echo "Run these commands on your LOCAL machine to connect:"
echo ""
echo "  scp pi@${PI_IP}:/etc/rancher/k3s/k3s.yaml ~/.kube/config-homelab"
echo "  sed -i '' 's/127.0.0.1/${PI_IP}/g' ~/.kube/config-homelab"
echo "  export KUBECONFIG=~/.kube/config-homelab"
echo "  kubectl get nodes"
echo ""
