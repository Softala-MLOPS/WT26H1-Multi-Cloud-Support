# Future backlog
## Completed (WT 26H1)
* ~~Succesfully run Oss-mlops-platform pipeline with multicloud pod offloading~~
  - ~~Check failed pod error messages from pod logs.~~ **Root cause found:** Pipeline uses hardcoded `svc.cluster.local` addresses that only resolve within cPouta. See Issue #43.
  - ~~Investigate and solve possible dependency problems with the external vm.~~ **Solved:** The fix is to offload the `mlflow` namespace using Liqo's Service Reflection with `--pod-offloading-strategy Local` and `--namespace-mapping-strategy EnforceSameName`. This makes MLflow services discoverable from cluster-b without moving pods. See Issue #44.
* ~~Tailor startup and setup scripts for vm that hosts external cluster.~~ **Done:** Created ClusterSetupVerda.sh which replaces the old Submariner-based script with Liqo. See Issue #51.
* ~~MVP example of GPU resource sharing (Issue #50).~~
  - ~~Create a Verda VM with GPU (e.g. Tesla V100)~~ **Done:** Created a Verda VM with Tesla V100-SXM2-16GB GPU.
  - ~~Get and install correct drivers and device plugins so k3s detects available GPU resources~~ **Done:** Installed NVIDIA container toolkit and deployed the device plugin with `runtimeClassName: nvidia` fix (required for k3s — without this the plugin cannot find the NVML library).
  - ~~Assert available GPU resources with Liqo so the consumer can detect providers resources via the created virtual node.~~ **Partially done:** Liqo does not automatically advertise GPU resources in the ResourceSlice. Manual workaround required: patch the ResourceSlice with `nvidia.com/gpu: 1` and label the virtual node with `nvidia.com/gpu=true`. See README Known Issues.
  - ~~Test with the fmnist GPU pipeline: https://github.com/OSS-MLOPS-PLATFORM/demo-fmnist-mlops-pipeline~~ **Done with Wine Quality pipeline instead:** The fmnist pipeline requires KFP v2 SDK rewrite (platform runs KFP v2.5.0 but pipeline uses v1.x). GPU scheduling was added to a copy of the Wine Quality pipeline (`demo_pipeline_gpu`). The training pod was successfully offloaded to the Verda Tesla V100 node while pull-data and preprocess ran on cPouta.
## Open items
* Run the full demo pipeline end-to-end with the service reflection fix applied. Verify all pipeline steps (pull-data, preprocess, train, evaluate, deploy, inference) complete successfully on cluster-b.
  - **Note from WT 26H1:** The deploy and inference steps currently fail due to a broken `kserve-controller-manager` pod (`ImagePullBackOff` caused by deprecated `gcr.io/kubebuilder` registry). 
* Migrate fmnist GPU pipeline to KFP v2: https://github.com/OSS-MLOPS-PLATFORM/demo-fmnist-mlops-pipeline
  - The fmnist pipeline was written for KFP v1 but the platform runs KFP v2.5.0. The pipeline needs to be rewritten using the KFP v2 SDK before it can run on this platform.
* The inference step in the pipeline uses `istio-ingressgateway.istio-system.svc.cluster.local`. If testing the full pipeline including inference, also offload `istio-system` namespace with the same Local strategy.
* Automated GPU VM lifecycle via polling script (investigated in WT 26H1): The goal is to automatically detect when a GPU workload is needed, spin up a Verda VM, run the training, and delete the VM when done, saving credits when idle. The recommended approach is Create/Delete VM each time (rather than Stop/Start) since it has zero idle cost, always starts fresh. Automatedverda.sh could also include the automation of fixing the stale nonce and setup time.

Detection: A Python polling script runs on cPouta, watching the kubeflow namespace for pods stuck in Pending state with the event message Insufficient nvidia.com/gpu. The VM is only created when a GPU pod is actually waiting.
Likely implementation flow:

1. Polling script detects a pending GPU pod (kubectl get events -n kubeflow --field-selector reason=FailedScheduling | grep nvidia.com/gpu)
2. Call Verda API to get an OAuth2 access token (POST /v1/oauth2/token with client_id and client_secret)
3. Call Verda API to create a GPU VM (POST /v1/instances with instance_type, image, ssh_key_ids, hostname, location_code)
4. Poll Verda API until VM status is running and get its public IP (GET /v1/instances/{instance_id})
5. Run setup-verda.sh <ip> <ssh_key> --gpu to peer the clusters and configure GPU
6. Pod gets scheduled on the Verda GPU node and training runs
7. Polling script detects training pod has completed
8. Call Verda API to delete the VM (PUT /v1/instances with action: delete) — zero idle credits consumed


Language: Python, using the official Verda Python SDK (https://github.com/verda-cloud/sdk-python) for API calls and subprocess for kubectl commands.
To implement: Requires Verda API credentials (client_id and client_secret from Verda console → Keys → Cloud API Credentials), the exact GPU instance type name, and the SSH key ID registered on Verda.


Investigate how Auto Scaling can be added to the system. This can include:

How does the system detect and decide when to scale?
Provisioning and creating new VM´s upon gpu / cpu load requirements.
Renting a Vm instance with automaticly scaling recourses by scaling and limiting the computing capacity of nodes. This can maby be done with Liqo ResourceSlice virtual nodes on consumer. You can assert the virtual nodes computing capacity even though truely capacity is greater.
A naming system for multiple VM´s, clusters, nodes and CIDR provisioning for non-overlapping addresses with different machines and clusters.


Investigate how to add automatic shut down and deletion for joined VM after determined time of provider node idle.

Do all created Vm´s have the same time of idle or does the potential idle time scale with somehow with the amount of instances active and idling.
Should the shutdown time be easily customizable by mlops user / admin


Investigate how to create a safe de-coupling and uninstalling script of the joined clusters to ensure succesful rejoining of clusters. (liqo specific problem). Note from WT 26H1: We experienced issues with stale peering state when doing unpeer/repeer cycles. The tenant namespace can get stuck in Terminating state. The workaround is to remove finalizers manually and force-delete the namespace. A clean uninstall/reinstall of Liqo on the consumer side resolves the issue completely. Additionally, a stale nonce secret (liqo-signed-nonce) in liqo-tenant-cluster-b must be deleted before re-peering a new VM with the same cluster-id.
Remote cluster is set up with k3s at the moment. Investigate if there is need for k8s. If the k3s doesn't have enough resources then modify the instructions to be compatible with k8s. Liqo can be deployed both k3s and k8s clusters.
