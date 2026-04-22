#!/bin/bash
set -euo pipefail

# ===== Verda VM Startup Script (Liqo) =====
# This script sets up a Verda VM as a Provider cluster for Liqo peering.
# It replaces the old ClusterSetupDC.sh which used Submariner.
#
# What this script does:
#   1. Installs system dependencies
#   2. Configures kernel for Kubernetes networking
#   3. Installs k3s
#   4. Installs liqoctl and Liqo
#   5. Exports kubeconfig with public IP
#   6. Optionally installs NVIDIA toolkit for GPU support
#   7. Installs NVIDIA device plugin with correct runtimeClassName
#   8. Fixes TLS certificate for public IP access
#
# After this script runs, you still need to:
#   - Transfer cluster-b.yaml to cPouta
#   - Run liqoctl peer from cPouta
#   - Run liqoctl offload commands from cPouta
#   - Patch ResourceSlice: kubectl patch resourceslice cluster-b -n liqo-tenant-cluster-b --type=merge -p '{"spec":{"resources":{"nvidia.com/gpu":"1"}}}'
#   - Label virtual node: kubectl label node cluster-b nvidia.com/gpu=true
#   - For GPU support: ENABLE_NVIDIA_TOOLKIT=true ./ClusterSetupVerda.sh
#
# Usage: Run as root on a fresh Ubuntu 24.04 VM on Verda
# ======================================================

LIQO_VERSION="${LIQO_VERSION:-v1.0.1}"
CLUSTER_ID="${CLUSTER_ID:-cluster-b}"
ENABLE_NVIDIA_TOOLKIT="${ENABLE_NVIDIA_TOOLKIT:-false}"
MARKER="/var/lib/verda-liqo-start.done"

log() { echo "[startup] $(date '+%H:%M:%S') $*"; }

# Skip if already ran
if [ -f "$MARKER" ]; then
    log "Setup already completed. Delete $MARKER to re-run."
    exit 0
fi

# ===== 1. System Dependencies =====
log "Installing system dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
    curl ca-certificates gnupg lsb-release jq iproute2 \
    iptables iputils-ping conntrack socat python3

# ===== 2. Kernel Configuration =====
log "Configuring kernel for Kubernetes networking..."
modprobe br_netfilter || true
echo br_netfilter > /etc/modules-load.d/k8s.conf
cat > /etc/sysctl.d/99-k8s.conf <<EOF
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
EOF
sysctl --system

# ===== 3. NVIDIA Toolkit (optional) =====
if [ "$ENABLE_NVIDIA_TOOLKIT" = "true" ]; then
    if ! command -v nvidia-ctk >/dev/null 2>&1; then
        log "Installing NVIDIA container toolkit..."
        dist=$(. /etc/os-release; echo ${ID}${VERSION_ID})
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
            | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        curl -fsSL "https://nvidia.github.io/libnvidia-container/stable/deb/${dist}/nvidia-container-toolkit.list" \
            | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#' \
            | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
        apt-get update -y
        apt-get install -y nvidia-container-toolkit
    else
        log "NVIDIA toolkit already installed."
    fi
else
    log "Skipping NVIDIA toolkit (set ENABLE_NVIDIA_TOOLKIT=true to install)"
fi

# ===== 4. Install k3s =====
if ! systemctl is-active --quiet k3s 2>/dev/null; then
    log "Installing k3s..."
    curl -sfL https://get.k3s.io | sh -

    # Configure NVIDIA runtime for k3s if toolkit is installed
    if [ "$ENABLE_NVIDIA_TOOLKIT" = "true" ] && [ -d /var/lib/rancher/k3s/agent/etc/containerd ]; then
        log "Configuring NVIDIA runtime for k3s..."
        cat > /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl <<CT
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
  runtime_type = "io.containerd.runc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
    BinaryName = "/usr/bin/nvidia-container-runtime"
CT
        systemctl restart k3s || true
    fi
else
    log "k3s already running."
fi

# ===== 5. Setup kubeconfig =====
log "Setting up kubeconfig..."
mkdir -p /root/.kube
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
chmod 600 /root/.kube/config

if id ubuntu >/dev/null 2>&1; then
    mkdir -p /home/ubuntu/.kube
    cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
    chown -R ubuntu:ubuntu /home/ubuntu/.kube
fi

# ===== 6. Install liqoctl =====
if ! command -v liqoctl >/dev/null 2>&1; then
    log "Installing liqoctl ${LIQO_VERSION}..."
    curl --fail -LS \
        "https://github.com/liqotech/liqo/releases/download/${LIQO_VERSION}/liqoctl-linux-amd64.tar.gz" \
        | tar -xz
    install -o root -g root -m 0755 liqoctl /usr/local/bin/liqoctl
    rm -f liqoctl
else
    log "liqoctl already installed."
fi

# ===== 7. Install Liqo on cluster =====
log "Installing Liqo with cluster-id: ${CLUSTER_ID}..."
liqoctl install k3s --cluster-id "${CLUSTER_ID}"

# ===== 8. Export kubeconfig with public IP =====
PUBLIC_IP=$(curl -sf http://checkip.amazonaws.com || curl -sf https://ifconfig.me || echo "UNKNOWN")
log "Detected public IP: ${PUBLIC_IP}"

cp /etc/rancher/k3s/k3s.yaml /root/cluster-b.yaml
chmod 600 /root/cluster-b.yaml
sed -i "s|server: https://127.0.0.1:6443|server: https://${PUBLIC_IP}:6443|" /root/cluster-b.yaml

log "kubeconfig exported to /root/cluster-b.yaml with public IP"

# ===== Fix TLS certificate for public IP access =====
# k3s generates a self-signed certificate for 127.0.0.1 by default.
# When connecting via public IP, certificate validation fails.
# This disables TLS verification so cPouta can connect without errors.
log "Disabling TLS verification for public IP access..."
kubectl config set-cluster default --insecure-skip-tls-verify=true
cp /root/.kube/config /root/cluster-b.yaml
sed -i "s|server: https://127.0.0.1:6443|server: https://${PUBLIC_IP}:6443|" /root/cluster-b.yaml
chmod 600 /root/cluster-b.yaml

# ===== Install NVIDIA device plugin (GPU support) =====
# The standard device plugin yaml does not work with k3s because it runs
# with the default container runtime instead of the NVIDIA runtime.
# Fix: download the yaml and add runtimeClassName: nvidia to the pod spec.
# Without this, the plugin cannot find the NVML library (libnvidia-ml.so.1)
# and the GPU is not advertised to Kubernetes.
if [ "$ENABLE_NVIDIA_TOOLKIT" = "true" ]; then
    log "Installing NVIDIA device plugin with runtimeClassName fix..."
    curl -o /tmp/nvidia-device-plugin.yml \
        https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.1/nvidia-device-plugin.yml
    sed -i 's/priorityClassName: "system-node-critical"/priorityClassName: "system-node-critical"\n      runtimeClassName: nvidia/' \
        /tmp/nvidia-device-plugin.yml
    kubectl apply -f /tmp/nvidia-device-plugin.yml
    log "NVIDIA device plugin installed."
fi

# ===== Done =====
touch "$MARKER"

log "============================================"
log "Verda VM setup complete!"
log "============================================"
log ""
log "Next steps (run from cPouta):"
log "  1. Transfer kubeconfig:  wget http://${PUBLIC_IP}:8080/cluster-b.yaml"
log "     (run 'python3 -m http.server 8080' on this VM first)"
log "  2. Peer:  liqoctl peer --kubeconfig ~/.kube/config --remote-kubeconfig ~/cluster-b.yaml"
log "  3. Offload namespaces:"
log "     liqoctl offload namespace kubeflow"
log "     liqoctl offload namespace mlflow --namespace-mapping-strategy EnforceSameName --pod-offloading-strategy Local"
log "  4. [GPU only] Patch ResourceSlice and label virtual node:"
log "     kubectl patch resourceslice cluster-b -n liqo-tenant-cluster-b --type=merge -p '{\"spec\":{\"resources\":{\"nvidia.com/gpu\":\"1\"}}}'"
log "     kubectl label node cluster-b nvidia.com/gpu=true"
log ""
log "Cluster ID: ${CLUSTER_ID}"
log "Public IP:  ${PUBLIC_IP}"
log "k3s:        $(kubectl get nodes -o wide 2>/dev/null | tail -1)"
log "Liqo:       $(liqoctl version 2>/dev/null | head -1)"
