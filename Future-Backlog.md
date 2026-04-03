# Future backlog

## Completed (WT 26H1)

* ~~Succesfully run Oss-mlops-platform pipeline with multicloud pod offloading~~
  - ~~Check failed pod error messages from pod logs.~~ **Root cause found:** Pipeline uses hardcoded `svc.cluster.local` addresses that only resolve within cPouta. See Issue #43.
  - ~~Investigate and solve possible dependency problems with the external vm.~~ **Solved:** The fix is to offload the `mlflow` namespace using Liqo's Service Reflection with `--pod-offloading-strategy Local` and `--namespace-mapping-strategy EnforceSameName`. This makes MLflow services discoverable from cluster-b without moving pods. See Issue #44.
* ~~Tailor startup and setup scripts for vm that hosts external cluster.~~ **Done:** Created ClusterSetupVerda.sh which replaces the old Submariner-based script with Liqo. See Issue #51.

## Open items

* Run the full demo pipeline end-to-end with the service reflection fix applied. Verify all pipeline steps (pull-data, preprocess, train, evaluate, deploy, inference) complete successfully on cluster-b.
* MVP example of GPU resource sharing (Issue #50).
  - Create a Verda VM with GPU (e.g. Tesla V100)
  - Get and install correct drivers and device plugins so k3s detects available GPU resources
  - Assert available GPU resources with Liqo so the consumer can detect providers resources via the created virtual node.
  - Test with the fmnist GPU pipeline: https://github.com/OSS-MLOPS-PLATFORM/demo-fmnist-mlops-pipeline
* The inference step in the pipeline uses `istio-ingressgateway.istio-system.svc.cluster.local`. If testing the full pipeline including inference, also offload `istio-system` namespace with the same Local strategy.
* Investigate how Auto Scaling can be added to the system. This can include:
  - How does the system detect and decide when to scale?
  - Provisioning and creating new VM´s upon gpu / cpu load requirements.
  - Renting a Vm instance with automaticly scaling recourses by scaling and limiting the computing capacity of nodes. This can maby be done with Liqo ResourceSlice virtual nodes on consumer. You can assert the virtual nodes computing capacity even though truely capacity is greater.
  - A naming system for multiple VM´s, clusters, nodes and CIDR provisioning for non-overlapping addresses with different machines and clusters.
* Investigate how to add automatic shut down and deletion for joined VM after determined time of provider node idle.
  - Do all created Vm´s have the same time of idle or does the potential idle time scale with somehow with the amount of instances active and idling.
  - Should the shutdown time be easily customizable by mlops user / admin
* Investigate how to create a safe de-coupling and uninstalling script of the joined clusters to ensure succesful rejoining of clusters. (liqo specific problem). **Note from WT 26H1:** We experienced issues with stale peering state when doing unpeer/repeer cycles. The tenant namespace can get stuck in Terminating state. The workaround is to remove finalizers manually and force-delete the namespace. A clean uninstall/reinstall of Liqo on the consumer side resolves the issue completely.
* Remote cluster is set up with k3s at the moment. Investigate if there is need for k8s. If the k3s doesn't have enough resources then modify the instructions to be compatible with k8s. Liqo can be deployed both k3s and k8s clusters.
