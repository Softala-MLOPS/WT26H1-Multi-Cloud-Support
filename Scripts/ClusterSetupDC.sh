#!/bin/bash
set -euo pipefail

# ===== Config =====
WG_IF="${WG_IF:-wg0}"
WG_ADDRESS="${WG_ADDRESS:-10.77.0.2/32}"
WG_PORT="${WG_PORT:-51820}"
WG_PRIVATE_KEY="${WG_PRIVATE_KEY:-CHANGEME_PRIVATE_KEY}"
PEER_PUBLIC_KEY="${PEER_PUBLIC_KEY:-CHANGEME_PEER_PUBLIC}"
PEER_ENDPOINT="${PEER_ENDPOINT:-csc.example.org:51820}"
PEER_ALLOWED_IPS="${PEER_ALLOWED_IPS:-10.77.0.1/32,10.42.0.0/16,10.96.0.0/12}"

K3S_CLUSTER_CIDR="${K3S_CLUSTER_CIDR:-10.43.0.0/16}"
K3S_SERVICE_CIDR="${K3S_SERVICE_CIDR:-10.97.0.0/16}"

ENABLE_NVIDIA_TOOLKIT="${ENABLE_NVIDIA_TOOLKIT:-true}"
BROKER_URL="${BROKER_URL:-}"
BROKER_PATH="${BROKER_PATH:-/root/broker-info.subm}"
CLUSTER_ID="${CLUSTER_ID:-datacrunch}"

MARKER="/var/lib/datacrunch-start.done"

log(){ echo "[startup] $*"; }

if [ -f "$MARKER" ]; then
  log "Marker exists, skipping."
else
  log "Running first boot setup."
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  curl ca-certificates gnupg lsb-release jq iproute2 iptables iputils-ping \
  wireguard wireguard-tools resolvconf conntrack socat

modprobe br_netfilter || true
echo br_netfilter >/etc/modules-load.d/k8s.conf
cat >/etc/sysctl.d/99-k8s.conf <<EOF
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
EOF
sysctl --system

if [ "$ENABLE_NVIDIA_TOOLKIT" = "true" ]; then
  if ! command -v nvidia-ctk >/dev/null 2>&1; then
    dist=$(. /etc/os-release; echo ${ID}${VERSION_ID})
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -fsSL "https://nvidia.github.io/libnvidia-container/stable/deb/${dist}/nvidia-container-toolkit.list" \
      | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#' \
      | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
    apt-get update -y
    apt-get install -y nvidia-container-toolkit
    nvidia-ctk runtime configure --runtime=docker || true
    systemctl restart docker || true
  fi
else
  log "Skipping NVIDIA toolkit"
fi

log "Configuring WireGuard"
mkdir -p /etc/wireguard && chmod 700 /etc/wireguard
WG_CONF="/etc/wireguard/${WG_IF}.conf"
cat >"$WG_CONF" <<EOF
[Interface]
Address = ${WG_ADDRESS}
ListenPort = ${WG_PORT}
PrivateKey = ${WG_PRIVATE_KEY}

[Peer]
PublicKey = ${PEER_PUBLIC_KEY}
AllowedIPs = ${PEER_ALLOWED_IPS}
Endpoint = ${PEER_ENDPOINT}
PersistentKeepalive = 25
EOF
chmod 600 "$WG_CONF"

if grep -q CHANGEME "$WG_CONF"; then
  log "WireGuard placeholders detected; skipping up."
else
  systemctl enable "wg-quick@${WG_IF}.service"
  systemctl restart "wg-quick@${WG_IF}.service" || true
fi

if ! systemctl is-active --quiet k3s; then
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--cluster-cidr ${K3S_CLUSTER_CIDR} --service-cidr ${K3S_SERVICE_CIDR}" sh -
  if [ "$ENABLE_NVIDIA_TOOLKIT" = "true" ]; then
    if [ -d /var/lib/rancher/k3s/agent/etc/containerd ]; then
      cat >/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl <<'CT'
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
  runtime_type = "io.containerd.runc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
    BinaryName = "/usr/bin/nvidia-container-runtime"
CT
      systemctl restart k3s || true
    fi
  fi
fi

mkdir -p /root/.kube
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
chmod 600 /root/.kube/config
if id ubuntu >/dev/null 2>&1; then
  mkdir -p /home/ubuntu/.kube
  cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
  chown -R ubuntu:ubuntu /home/ubuntu/.kube
fi

JOINED_MARK="/var/lib/submariner.joined"
if [ ! -f "$JOINED_MARK" ]; then
  if [ -n "$BROKER_URL" ] && [ ! -s "$BROKER_PATH" ]; then
    curl -fsSL "$BROKER_URL" -o "$BROKER_PATH" || true
  fi
  if [ -s "$BROKER_PATH" ]; then
    curl -Ls https://get.submariner.io | bash
    if [ -f ./subctl ]; then install -m 0755 ./subctl /usr/local/bin/subctl; rm ./subctl; fi
    subctl join --kubeconfig /root/.kube/config --clusterid "${CLUSTER_ID}" \
      --natt enable --broker-info "$BROKER_PATH" || true
    touch "$JOINED_MARK"
  fi
fi

touch "$MARKER"
log "Startup complete."