#!/bin/bash

VERDA_IP="${1:-}"
SSH_KEY="${2:-}"
GPU_MODE="${3:-}"

if [ -z "$VERDA_IP" ] || [ -z "$SSH_KEY" ]; then
    echo "Usage: $0 <verda_public_ip> <ssh_key_path> [--gpu]"
    exit 1
fi

SSH_CMD="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no root@${VERDA_IP}"

# Copy and run ClusterSetupVerda.sh on Verda
scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no ClusterSetupVerda.sh root@${VERDA_IP}:/root/

if [ "$GPU_MODE" = "--gpu" ]; then
    $SSH_CMD "chmod +x /root/ClusterSetupVerda.sh && ENABLE_NVIDIA_TOOLKIT=true /root/ClusterSetupVerda.sh"
else
    $SSH_CMD "chmod +x /root/ClusterSetupVerda.sh && /root/ClusterSetupVerda.sh"
fi