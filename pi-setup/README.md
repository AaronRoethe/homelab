# Pi Setup

Bootstrap a Raspberry Pi from fresh OS install to running k3s cluster.

## Prerequisites

- Raspberry Pi 4/5 with 8GB RAM
- Raspberry Pi OS Lite 64-bit (Bookworm) flashed to SD card
- SSH enabled (add empty `ssh` file to boot partition)
- Network connectivity

## Usage

SSH into the Pi and run:

```sh
./install.sh
```

This runs the following scripts in order:

1. **01-system-prep.sh** - OS tuning, cgroups, disable swap, install packages
2. **02-k3s-install.sh** - Install k3s with Pi-optimized flags
3. **03-post-install.sh** - Verify cluster, print kubeconfig instructions

## After Setup

Copy the kubeconfig to your local machine:

```sh
scp pi@homelab.local:/etc/rancher/k3s/k3s.yaml ~/.kube/config-homelab
```

Edit the file and replace `127.0.0.1` with your Pi's IP address, then:

```sh
export KUBECONFIG=~/.kube/config-homelab
kubectl get nodes
```
