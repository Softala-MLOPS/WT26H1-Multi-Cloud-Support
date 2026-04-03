# Other investigated and tested solutions

These solutions have been tested and found inoperative for this multi-cloud solution.

## WireGuard & Submariner

Submariner doesn't suit for this use because it only connects the clusters. It does not provide a way to share resource usage or offloading between clusters like Liqo. However, below are our findings and the solution with which we managed to connect the clusters.

## Environment for Submariner connecting
### Development Environment n.1
 - 2 Openstack VMs in this case CSC cPouta
 - Ubuntu 24.04 Lts
 - 32 GB ram 
 - 80 GB disk space
 - 8 VCPU
 - ssh commandline connection 
## API requirements
## Technology Stack
 - Kind
 - K8s
 - Submariner
 - WireGuard
 - Docker
 - kubectl
 - curl
 
# Required Features
## Setting up cPouta VMs
 
 1. Create 2 new projects at CSC
 2. Create virtual machines on both projects using cPouta [Guide](https://docs.csc.fi/cloud/pouta/launch-vm-from-web-gui/). (Windows Powershell in our case)
 3. Connect to VMs with ssh via local powershell. cPuota [Guide](https://docs.csc.fi/cloud/pouta/connecting-to-vm/)

Authors: Kosti Kangasmaa and Jouni Tuomela

## Setting up WireGuard
 We need WireGuard tunnel for Multi-Cloud-Feature because we need to access vm-a from vm-b and vice versa for ease of use and also to host Submariner Broker API at an address that both VMs see
 - You are connected on VM via ssh setting up is faster when done with a pair because we need to run commands on both VMs.
 - WireGuard requires root user access to work. We want to change user´s on both VMs.
 - Keep the private keys secret and in case of a leak change the private and public keys.
   
```bash
  sudo -i
  ```

 - Update apt and Install WireGuard
  
```bash
  apt update
  apt install WireGuard
  ```
- generate WireGuard private keys and public keys from them on both vm´s
```bash
  cd /home/etc/wireguard
  umask 077
  wg genkey | tee private.key | wg pubkey > public.key
```
- Create WireGuard configuration files on both VMs, name of the file determines name of tunnel.
- Conf files are needed to use wg-quick utility [manual](https://man7.org/linux/man-pages/man8/wg-quick.8.html)
```bash
cd /home/etc/wireguard
nano wg0.conf
```
- Fill the conf file with the required information. keys can be accessed with commands and floating ips can be accessed by CSC instances

```bash
cat private
cat public
```
- Vm-a's conf example 
```
[Interface]

PrivateKey = aLlmR+Kbeb3tsadfasdlgnaslkdgjlkasndlfansdflkjnDkw= #placeholder for your private key

Address = 10.0.0.1/24 #vm-a future WireGuard tunnel CIDR

ListenPort = 56949 #UDP port chosen for tunnel pick a port that is not occupied higher numbers usually are free
 
[Peer]

PublicKey = K5dvexBv4p1asdfjashdfkjashfdkjasdhkfjak9fcVjo= #placeholder for vm-b's public key

Endpoint = 86.52.21.44:56949 #vm-b public ip (floating ip from CSC) and UDP port

AllowedIPs = 10.0.0.2/32 #vm-b future CIDR that will connect to the tunnel
 
```
- VM-B's conf example

```
[Interface]

PrivateKey = aLlmR+Kbeb3tsadfasdlgnaslkdgjlkasndlfansdflkjnDkw= #placeholder for your private key

Address = 10.0.0.2/24 #VM-B future WireGuard tunnel CIDR

ListenPort = 56949 #UDP port chosen for tunnel pick a port that is not occupied higher numbers usually are free
 
[Peer]

PublicKey = K5dvexBv4p1asdfjashdfkjashfdkjasdhkfjak9fcVjo= #placeholder for VM-A's public key

Endpoint = 86.62.81.124:56949 #VM-A's public ip (floating ip from CSC) and UDP port

AllowedIPs = 10.0.0.1/32 #VM-A future CIDR that will connect to the tunnel
```
- Next we need to Create a new Openstack security groups on CSC for both VMs. Name the group as WireGuard
- VM-A
  - Ingress 	IPv4 	UDP PORT=56949 VM-B's-public-ip as remote=86.52.21.44
  - Egress 	IPv4 	UDP PORT=56949 VM-A's-public-ip as remote=86.62.81.124
- VM-B
  - Ingress 	IPv4 	UDP PORT=56949 VM-A's-public-ip as remote=86.62.81.124
  - Egress 	IPv4 	UDP PORT=56949 VM-B's-public-ip as remote=86.52.21.44

- Apply said groups to VM instances
- Then run wg-quick on both VMs
```bash
wg-quick up wg0
```
- Inspect WireGuard info with wg

![wg](/images/wg.png)

- You should be able to ping VM-B from VM-A with its tunnel ip

```bash
ping 10.0.0.2
```

![wg-ping](/images/wg-ping.png)
Authors: Kosti Kangasmaa and Jouni Tuomela

## Allow vm-a to connect to vm-b
These instructions are meant only for CSC's cPouta virtual machines.

They configure vm-b to accept SCP connection from vm-a using password authentication instead of SSH keys.

#### Switch to root user on vm-b
```bash
sudo -i
  ```
- You’ll enter the root shell to perform system-level changes.

#### Create a new user for SSH/SCP access
```bash
adduser <username>
  ```
- Ubuntu will prompt you to set and confirm a password.

- After that, it will ask for optional user information — just press Enter to skip.

- Finally, confirm with Y when asked if the information is correct.

- You should see:
```
passwd: password updated successfully
```
#### Enable password authentication for SSH
- Navigate to SSH configuration directory:
```bash
cd /etc/ssh/sshd_config.d
  ```
![wg-ping](/images/navigate.png)
- Edit the cloud image configuration file:
```bash
 nano 60-cloudimg-settings.conf
  ```
- Change its contents to:
```bash
PasswordAuthentication yes
  ```
![wg-ping](/images/password_authentiction.png)
- Confirm changes 
```
  CTRL + O
  ```
- Name the file 
```
  ENTER
  ```
- Exit the file
```
  CTRL + X
  ```
- This overrides the default cPouta settings (which disables password logins for security reasons)
#### Restart SSH service
```bash 
  systemctl restart ssh
  ```
#### Result
- Now vm-a can connect to vm-b using SCP or SSH with the credential of the newly created user:
```bash
scp <file> <username>@<vm-b-ip>:<destination>
  ```
#### Security note
- Password authentication should be enabled only for internal testing or controlled environments like cPouta VMs.

- In production systems, prefer SSH key-based authentication for security.

Author: Jouni Tuomela

## Submariner sandbox with WireGuard that Submariner handles with 2 different Vm's on Openstack
Start by installing required technology stack, this demo has been done on versions stated below.
  
  - Docker version 28.5.1, build e180ab8
  - Kind kind version 0.30.0
  - Kubectl
    Client Version: v1.34.1
    Kustomize Version: v5.7.1
  - WireGuard & WireGuard-tools v1.0.20210914
  - subctl version v0.21.0
  - Existing WireGuard tunnel between VMs
  
### Creating clusters with kind
- Start by creating config files that the clusters are built with.
#### VM-A
```Bash
nano cluster-a-kind.yaml
```
- The broker api of Submariner is hosted inside our existing WireGuard tunnel on vm-a at 10.0.0.1:6443 so it is discoverable on vm-b.
- The created subnets should not overlap with vm-b's clusters subnets.
- UDP ports 4500 and 4490 are for routing the WireGuard tunnel Submariner creates.

```
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: "10.0.0.1"
  apiServerPort: 6443
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
nodes:
- role: control-plane
- role: worker
  extraPortMappings:
  - containerPort: 4500
    hostPort: 4500
    protocol: UDP
  - containerPort: 4490
    hostPort: 4490
    protocol: UDP
```
- Create the cluster from config file

```bash
kind create cluster --name cluster-a --config cluster-a-kind.yaml
```
- To use created cluster

```bash
kubectl cluster-info --context kind-cluster-a
```
- Next we need to label the workernode as a gateway node for Submariner traffic

```bash
kubectl --context kind-cluster-a label node cluster-a-worker Submariner.io/gateway=true --overwrite
```
- Lets deploy Submariner broker and join our cluster-a to it
- Deploying broker creates a brokerfile broker-info.subm and we use that file for joining all clusters including clusters on different VMs

```bash
subctl deploy-broker
```
-   Next we join cluster-a to the broker with brokerfile

```bash
 subctl join broker-info.subm --context kind-cluster-a --clusterid vm-a --cable-driver wireguard
```
![subctl join vm-a](/images/subctl-join-vm-a.png)
- We can look up info and diagnostics about our Submariner with the commands
```bash
subctl show all
subctl diagnose all
```
- To join clusters on other VM we need to send the brokerfile to the VM we are joining clusters on with scp for example

```bash
scp broker-info.subm <user>@<VM-b´s ip>:~/
```

#### VM-B

```bash
nano cluster-b-kind.yaml
```
- Different subnets for cluster-b
```
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  podSubnet: "10.245.0.0/16"
  serviceSubnet: "10.80.0.0/12"
nodes:
- role: control-plane
- role: worker
  extraPortMappings:
  - containerPort: 4500
    hostPort: 4500
    protocol: UDP
  - containerPort: 4490
    hostPort: 4490
    protocol: UDP
```
- Create the cluster from config file

```bash
kind create cluster --name cluster-b --config cluster-b-kind.yaml
```
- To use created cluster

```bash
kubectl cluster-info --context kind-cluster-b
```
- Next we need to label the workernode as a gateway node for Submariner traffic

```bash
kubectl --context kind-cluster-b label node cluster-b-worker Submariner.io/gateway=true --overwrite
```
- To join vm-b's cluster to vm-a's cluster via Submariner broker with Submariner we need to have the brokerfile that vm-a has created when deploying the broker
- Join cluster-b with brokerfile

```bash
subctl join broker-info.subm --context kind-cluster-b --clusterid vm-b --cable-driver wireguard
```
- Connection takes few seconds, but to confirm and diagnose Submariner connection on either VM.

```bash
subctl show all
```
![subctl show all](/images/subctl-show-all-vm-a.png)

```bash
subctl diagnose all
```
![subctl diagnose all](/images/subctl-diagnose-all-vm-a.png)

Now the connections should be up and running.

Author: Kosti Kangasmaa

## StartUp Script with Submarine on Verda
![StartUpScript FlowChart](/images/FlowChartDC_Startup25new.png)

Check code: [startup script with submarine](./Scripts/ClusterSetupDC.sh)!

Current version does not support logs, but you can check that everything gets installed with:
```bash
echo -e "\n====== [1] SCRIPT MARKER ======"; \
if [ -f /var/lib/Verda-start.done ]; then echo "Startup script marker found"; else echo "Marker missing"; fi; \
echo -e "\n====== [2] WIREGUARD ======"; \
if command -v wg >/dev/null 2>&1; then echo "wg version: $(wg --version 2>/dev/null)"; sudo systemctl --no-pager status wg-quick@wg0 2>/dev/null | grep -E "Active|Loaded" || true; echo; sudo wg show || echo "No wg interface running"; else echo "wg not installed"; fi; \
echo -e "\n====== [3] DOCKER ======"; \
if command -v docker >/dev/null 2>&1; then docker --version; docker info --format 'CgroupDriver={{.CgroupDriver}}  Runtimes={{.Runtimes}}'; else echo "docker not installed"; fi; \
echo -e "\n====== [4] K3S / KUBERNETES ======"; \
if systemctl list-units --type=service | grep -q k3s; then sudo systemctl is-active k3s >/dev/null && echo "k3s service active" || echo "k3s service inactive"; sudo k3s kubectl get nodes -o wide 2>/dev/null || sudo kubectl get nodes -o wide 2>/dev/null || echo "kubectl not available"; else echo "k3s not installed"; fi; \
echo -e "\n====== [5] SUBMARINER ======"; \
if command -v subctl >/dev/null 2>&1; then echo "subctl version: $(subctl version 2>/dev/null)"; sudo subctl show all 2>/dev/null || echo "No broker joined yet"; else echo "Submariner not installed (expected if no broker file)"; fi; \
echo -e "\n====== [6] SUMMARY ======"; \
ip a show wg0 2>/dev/null | grep inet || echo "No wg0 address"; \
sudo kubectl get pods -A 2>/dev/null | head -10 || sudo k3s kubectl get pods -A 2>/dev/null | head -10 || echo "No pods listed"; \
echo -e "\n Diagnostics complete."
```

### Author

**Eemil Airaksinen**

---
