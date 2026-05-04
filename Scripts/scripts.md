## Scripts

- **ClusterSetupVerda.sh** - Verda VM startup script with Liqo (current). Automates k3s installation, liqoctl setup, Liqo installation, and kubeconfig export with public IP. Can be used as a Verda startup script or run manually.
- **AutomatedVerda.sh** - Automation script that runs from cPouta to remotely set up a Verda VM. It copies ClusterSetupVerda.sh to the Verda VM via SCP and runs it remotely via SSH. Requires the Verda VM to already be running. Usage:
```bash
  # Make executable (only needed once)
  chmod +x setup-verda.sh

  # CPU node
  ./setup-verda.sh  

  # GPU node
  ./setup-verda.sh   --gpu
```
 *After running AutomatedVerda.sh — Manual steps on cPouta

Once `setup-verda.sh` has completed, run the following commands on cPouta:

 1. Download kubeconfig from Verda
```bash
wget http://:8080/cluster-b.yaml
```

 2. Delete stale nonce secret (always run this before peering)
```bash
kubectl delete secret liqo-signed-nonce -n liqo-tenant-cluster-b 2>/dev/null || true
```

 3. Peer the clusters
```bash
liqoctl peer --kubeconfig ~/.kube/config --remote-kubeconfig ~/cluster-b.yaml
```

 4. Offload namespaces
```bash
liqoctl offload namespace kubeflow --namespace-mapping-strategy EnforceSameName --pod-offloading-strategy Local

liqoctl offload namespace mlflow --namespace-mapping-strategy EnforceSameName --pod-offloading-strategy Local
```

 5. GPU only — Patch ResourceSlice and label virtual node
```bash
kubectl patch resourceslice cluster-b -n liqo-tenant-cluster-b --type=merge -p '{"spec":{"resources":{"nvidia.com/gpu":"1"}}}'

kubectl label node cluster-b nvidia.com/gpu=true --overwrite
```

 6. Verify everything is working
```bash
liqoctl info
kubectl get nodes
```
  Note: `ClusterSetupVerda.sh` must be in the same folder as `setup-verda.sh`.
  
- **ClusterSetupDC.sh** - Old startup script with Submariner (deprecated). Kept for historical reference.
  
