# Multi-cloud demo
This is a step-by-step guide for connecting an external k3s cluster to Oss-mlops-platforms k8s cluster running on my CSC cPouta vm. The goal of this demo is to work as an proof of concept for offloading workloads from Oss-mlops-platform ml development pipeline to an external cluster which is located on seperate VM on a different cloud provider. This is achieved with connecting the two clusters with Liqo. Liqo also handles:
* Vpn tunnel for intercluster connections.
* Setup and management of a virtual node.
* Namespace extending between nodes.
* Offloading strategy for pods under said namespace.

## Technologies added to Oss-mlops-platform Stack

* K3s
* liqo
* liqoctl (multicluster networking + scheduling)
* Helm (indirectly used by liqoctl)
* WireGuard (built-in) – created automatically by Liqo for cross-cluster VPN

## Development Environments
### Key requirement
* One of the VMs has to have public IP-address. If both of the machines are using NAT(Network Address Translation) the connection can't be established.
* **My CSC cPouta IS behind NAT**
### Environment 1. Consumer-Vm  k8s Oss-mlops-platform (My CSC cPouta)

VM specs:

| Component | |
| --------- | --------- |
| Cloud provider | my CSC cPouta |
| RAM       | 32 GB     |
| vCPUs     | 8         |
| Disk      | 80 GB     |
| Network   | Floating IP (NAT) |
| OS | Ubuntu 24.04 LTS |
|Kubernetes distribution| k8s kind |

### Environment 2. Provider-Vm k3s cluster-b (Verda)
VM specs:

| Component | |
| --------- | --------- |
| Cloud provider | Verda |
| RAM       | 16 GB (minimum for testing) |
| vCPUs     | 4 (minimum for testing)     |
| Disk      | 50 GB     |
| Network   | Public IP (ipv4) |
| OS | Ubuntu 24.04 LTS |
|Kubernetes distribution| k3s |

## Architecture Overview
![mlops_cluste_federation](/images/mlops_cluster_federation.png)

### Chart created by

**Jouni Tuomela**



# Setup Guide

## 1. Kubernetes Setup for OSS-MLops-Platform and Verda
 
### **Consumer Cluster (kind-mlops-platform / Cpouta-vm)**
 
Only requirement is that the OSS-MLOps Platform repository is cloned and installed correctly.
 
Install reference: https://github.com/OSS-MLOPS-PLATFORM/oss-mlops-platform/blob/main/tools/CLI-tool/Installations%2C%20setups%20and%20usage.md
 
### **Provider Cluster (cluster-b / Verda-vm)**

You can either run the automated startup script or set up manually.

#### Option A: Automated setup (recommended)

Use the startup script as a Verda startup script or run it manually after SSH-ing in:

```bash
bash ClusterSetupVerda.sh
```

See [Scripts/ClusterSetupVerda.sh](./Scripts/ClusterSetupVerda.sh) for the full script.

#### Option B: Manual setup
 
Update system packages:
 
```bash
apt update
```
 
Install Python and pip (required by OSS-MLOps Platform)
 
```bash
apt install -y python3 python3-pip
```
 
Verify:
 
```bash
python3 --version
pip3 --version
```
 
Download and install kustomize:
 
```bash
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -s -- 5.2.1
v5.2.1
chmod +x ./kustomize
mv ./kustomize /usr/local/bin/kustomize
```
 
Verify:
 
```bash
kustomize version
```
 
Install k3s:
 
```bash
curl -sfL https://get.k3s.io | sh -
```
 
Export kubeconfig:
 
```bash
sudo cat /etc/rancher/k3s/k3s.yaml > ~/cluster-b.yaml
chmod 600 ~/cluster-b.yaml
```
 
Prepare kubectl directory:
 
```bash
mkdir -p /root/.kube
sudo cat /etc/rancher/k3s/k3s.yaml > /root/.kube/config
```

## 2. Install liqoctl

On BOTH Vm´s:

```bash
curl --fail -LS \
  "https://github.com/liqotech/liqo/releases/download/v1.0.1/liqoctl-linux-amd64.tar.gz" \
  | tar -xz

sudo install -o root -g root -m 0755 liqoctl /usr/local/bin/liqoctl
```

Verify:

```bash
liqoctl version
```

Expected:

```
Client version: v1.0.1
Server version: Unknown
```

(Server version appears after installing Liqo.)

## 3. Install Liqo on both clusters

### Oss-mlops-platform (consumer)

Get Oss-mlops-platfor specific CIDRs
```bash
kubectl get nodes -o jsonpath='{.items[0].spec.podCIDR}'
echo
```
```bash 
kubectl cluster-info dump | grep -m1 -E "service-cluster-ip-range|serviceSubnet"
```
![get-cidrs](/images/kubectl-get-CIDR.png)

```bash
liqoctl install --cluster-id kind-mlops-platform --pod-cidr 10.244.0.0/24 --service-cidr 10.96.0.0/16
```

![liqoctl-install-mlops](/images/liqoctl-install-mlops-platform.png)

Verify with liqoctl info:
```bash
liqoctl info
```

![liqoctl-info-mlops-platform](/images/liqoctl-info-mlops-platform.png)

### Cluster-b (provider)

```bash
liqoctl install k3s --cluster-id cluster-b
```



## 4. Transfer Cluster-b Kubeconfig to Oss-mlops-platform
In this case we serve it via http.server, but it can be transfered with SCP for example.

On **Cluster-b**:

```bash
python3 -m http.server 8080
```

Output:

```
Serving HTTP on 0.0.0.0 port 8080...
```

On **Oss-mlops-platform**:

Download the kubeconfig

```bash
wget http://<Cluster-b-public-ip>:8080/cluster-b.yaml -O cluster-b.yaml
```

For example in our case:

```
86.38.238.14
```

Verify:

```bash
ls -l cluster-b.yaml
```

## 5. Fix certificate validation (Rewrite server IP in cluster-b.yaml)

On **Oss-mlops-platform**, modify cluster-b.yaml

```bash
nano cluster-b.yaml
```

Change server address to:

```
server: https://<Cluster-b-public-ip>:6443
```
![cluster-b](/images/cluster-b-yaml.png)

Verify connection:

```bash
kubectl --kubeconfig cluster-b.yaml get nodes
```
![kubectl-verify](/images/kubectl-get-nodes-verify.png)

If nodes appear → **certificates OK**.

## 6. Establish Liqo Peering 

On Oss-mlops-platform:

```bash
liqoctl peer \
  --kubeconfig ~/.kube/config \
  --remote-kubeconfig cluster-b.yaml
```

![liqoctl-peer](/images/liqoctl-peer.png)



### Validate Peering on both Vm´s
```bash
liqoctl info
```



![liqoctl-peering](/images/liqoctl-info-peering-mlops.png)


![liqoctl-peering](/images/liqoctl-info-peering-verda.png)


## 7. Pod Scheduling to Cluster-b

Liqo requires namespaces to be offloaded before scheduling. Mlops platform schedules training workloads under kubeflow namespace. Liqo´s default offloading strategy is **LocalAndRemote** which schedules future pods in the node in said namespace that has most recources available.

### Step 1 — Offload namespaces

On Oss-mlops-platform:

```bash
liqoctl offload namespace kubeflow
```

This:

* Enables cross-cluster scheduling
* Creates a twin namespace on Cluster B
* Removes the Liqo protective taint
* Enables automatic remote scheduling

### Step 2 — Enable cross-cluster service discovery (IMPORTANT)

The demo pipeline references MLflow and Minio using Kubernetes internal DNS names (`mlflow.mlflow.svc.cluster.local`, `mlflow-minio-service.mlflow.svc.cluster.local`). These services run in the `mlflow` namespace on cPouta and are not visible from cluster-b by default.

To make them accessible, offload the `mlflow` namespace with **Local pod strategy** (keeps MLflow pods on cPouta, only mirrors the Service to cluster-b):

```bash
liqoctl offload namespace mlflow \
  --namespace-mapping-strategy EnforceSameName \
  --pod-offloading-strategy Local
```

This uses Liqo's Service Reflection feature to replicate the Service and EndpointSlice resources to cluster-b, while the actual MLflow pods stay on cPouta. The `EnforceSameName` strategy ensures the namespace name is identical on both clusters, so `svc.cluster.local` DNS resolution works as expected.

Reference: https://docs.liqo.io/en/stable/examples/service-offloading.html

**Note:** If the pipeline also uses the inference step (KServe via Istio), you may also need:

```bash
liqoctl offload namespace istio-system \
  --namespace-mapping-strategy EnforceSameName \
  --pod-offloading-strategy Local
```

**Without this step, pods offloaded to cluster-b will fail with `Name or service not known` when trying to reach MLflow.**

### Step 3 — Run test workload (Wine Quality / Demo pipeline)

### Install JupyterLab Desktop

First, download and install JupyterLab Desktop to your local machine:

https://github.com/jupyterlab/jupyterlab-desktop

### Port-forward Kubeflow and MLflow services

Run in terminal window:

```bash
kubectl -n mlflow port-forward svc/mlflow 5000:5000
```
Open a new terminal window and run:

```bash
kubectl -n kubeflow port-forward svc/ml-pipeline-ui 8080:80
```
After this step you should be able to connect to the Kubeflow interface from http://localhost:8080/

More info on port-forwarding:

```bash
https://github.com/OSS-MLOPS-PLATFORM/oss-mlops-platform/blob/main/tools/CLI-tool/Installations%2C%20setups%20and%20usage.md
```

### Clone the OSS MLOps Platform repository

Clone the repository that contains the demo:

```bash
git clone https://github.com/OSS-MLOPS-PLATFORM/oss-mlops-platform.git
```
Open the cloned oss-mlops-platform folder directly in JupyterLab Desktop.

Once opened:

* Restart the kernel

* Ensure the correct Python environment is selected

You can now test the cluster by running the demo pipeline notebook.

### Step 4 — Verify scheduling

#### On Oss-mlops-platform:

```bash
kubectl get pods -n kubeflow -o wide
```

![kubeflow-mlops](/images/kubeflow-mlops-o-wide.png)

#### On Cluster-b:
```bash
kubectl get pods --all-namespaces -o wide
```

![kubeflow-verda](/images/kubeflow-verda.png)

#### Offloading overview

![offloading_chart](/images/offloading_chart.png)

### Chart created by

**Jouni Tuomela**
  
## Create and set up instance on Verda manually

 1. Set up SSH-keys for SSH Connection between Verda and your local machine (to debug and work manually):  
 **Project page (Cloud Project) > Keys > SSH KEYS > +Create**
 2. Create Instance:   
    - Project page (Cloud Project) > Instances > +Create Instance
    - On-Demand or Spot > Pay As You Go > CPU Node (for testing) or lowest hourly price with least possible GPUs
    - Fixed pricing > Closest location (fin) > Ubuntu 24.04 (or use same version on both clusters) + latest CUDA + Docker + 50GB
    - SSH Keys > Add your keys
    - Startup script > Add a new script (find latest working script from here): https://github.com/Softala-MLOPS/Multi-Cloud-Support/blob/main/Scripts/scripts.md
    - Deploy now
 3. Usually it will take up to 3 minutes for instance to deploy. After you see it running, you can find info for SSH connection from settings of instance and you can use same user than you did setup on SSH-KEYS.

_If you want to use a visual desktop interface, you can find guide here:_
https://docs.verda.com/cpu-and-gpu-instances/remote-desktop-access

## Image sharing on MyCSC

### Image sharing between cPouta projects
Image sharing between projects is currently not supported using the Pouta web interface. However sharing can be done by using OpenStack CLI and OpenStack RC File that is found inside project API Access. Using Python virtual environment is recommended. Links below helps to install and use CLI:  
https://docs.csc.fi/cloud/pouta/install-client/

"Sharing images between Pouta projects" at bottom of the web page:  
https://docs.csc.fi/cloud/pouta/adding-images/#sharing-images-between-pouta-projects

### Image download to cPouta project
If you don't want to start fresh, you can try to use current state of mlops-pouta image found from teams WT 25H2 - MULTI-CLOUD SUPPORT shared files and use it on your cPouta project:   
**Project > Compute > Images > + Create Image**

#### !!NOTE: OpenStack CLI does not give you any responses from invalid logins or most commands!!

### Author(s)

**Brown Ikechukwu Aniebonam, Kosti Kangasmaa, Jouni Tuomela and Eemil Airaksinen** (WT 25H2)

**Qi Zhen and Emanuela Luciani** (WT 26H1)

---
