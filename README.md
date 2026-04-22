# Multi-Cloud-Support

Repository for OSS MLOps Multi-Cloud Support sub group.

The goal of the group is to find a solution for sharing Kubernetes resources between clusters. The main goal is to offload additional resources to clusters which have available resources.

For connecting the clusters and resource sharing, we have selected open-source software Liqo, as it handles both.

The testing environment is a cPouta VM in CSC and a VM in Verda. The Consumer cluster runs k8s with kind (OSS-MLOps-Platform) on cPouta, and the Provider cluster runs k3s on Verda, orchestrated by Liqo.

## Current status (WT 26H1)

Building on the previous team's (WT 25H2) proof of concept, we identified and resolved the pod offloading failure:

- **Root cause identified (Issue #43):** The demo pipeline contains hardcoded `svc.cluster.local` addresses pointing to MLflow and Minio services. These DNS names only resolve within the cPouta cluster. When pods are offloaded to Verda, they cannot reach these services.
- **Solution implemented (Issue #44):** Using Liqo's Service Reflection feature, we offload the `mlflow` namespace with `--pod-offloading-strategy Local` and `--namespace-mapping-strategy EnforceSameName`. This mirrors the MLflow service to cluster-b without moving pods, making `mlflow.mlflow.svc.cluster.local` resolvable from Verda. No pipeline code changes needed.
- **Startup script migrated (Issue #51):** Created a new Liqo-based startup script for Verda VMs, replacing the old Submariner-based script. The new script also supports GPU setup via ENABLE_NVIDIA_TOOLKIT=true.
- **GPU resource sharing demonstrated: ** Successfully offloaded the training step of the Wine Quality pipeline to a Verda VM with a Tesla V100 GPU. Pull-data and preprocess steps run on cPouta, while the training pod is scheduled on the Verda GPU node via Liqo virtual node. Key fixes required:

- **NVIDIA device plugin must be deployed with runtimeClassName: nvidia (k3s-specific fix)**
1. Liqo ResourceSlice must be patched to advertise GPU resources: nvidia.com/gpu: 1
2. Virtual node must be labeled: nvidia.com/gpu=true
3. TLS certificate issue fixed by setting insecure-skip-tls-verify=true in kubeconfig
4. Stale nonce secret must be deleted before re-peering: kubectl delete secret liqo-signed-nonce -n liqo-tenant-cluster-b

## Documentation

- [Demo Guide](Multi-cloud-poc-demo.md) - Step-by-step setup and usage instructions (updated with service reflection fix)
- [Future Backlog](Future-Backlog.md) - Next steps for future teams
- [Failed Investigations](Failed-investigations.md) - Solutions that were tested and found inoperative

## Known Issues

- KServe deployment step fails: The kserve-controller-manager pod is in ImagePullBackOff because gcr.io/kubebuilder/kube-rbac-proxy:v0.13.1 is no longer available (Google deprecated the registry). Patching to quay.io/brancz/kube-rbac-proxy:v0.13.1 fixes the image pull but the manager container still crashes. 
- Stale peering state: When deleting and recreating a Verda VM with the same cluster-id, the nonce secret from the previous peering remains on cPouta and causes authentication failures. Always run kubectl delete secret liqo-signed-nonce -n liqo-tenant-cluster-b before re-peering.
- GPU resources not advertised by Liqo: Liqo does not automatically include extended resources (like GPUs) in the ResourceSlice. After peering, manually patch the ResourceSlice and label the virtual node (see ClusterSetupVerda.sh next steps).

## Verda API and possible usages

Before you can use REST API:
1. Get Credentials from the Verda Cloud Dashboard
2. Generate Access Token

More in-depth guidance and about every usage of API:
https://api.verda.com/v1/docs#description/verda-cloud

Potential API Endpoints for Integration:
- Instances: Get instances, Deploy instances, Perform action on instance or multiple instances, Get instance by ID
- Instance Availability (if current option is not available)

Setups for SSH and startup scripts can be done via dashboard.

Scaling will be handled on cPouta (cluster A) by deploying and deleting instances (instance needs to be totally removed, or else it will still use credits from project's balance!)
