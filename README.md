# Kubernetes Multi-Node Cluster Installation Steps.

*This guide provides the steps to install and configure a Kubernetes cluster. Follow these instructions to set up a master node and worker nodes.*

## Prerequisites:


Prerequisites
### 1. Rocky Linux OS
- Ensure that Rocky Linux is installed on each VM for both master and worker nodes.

### 2. Virtual Machines:

- A minimum of two VMs is required:
   - *Master Node VM: The central control plane for the Kubernetes cluster.*
   - *Worker Node VM: A machine that will join the cluster and run containerized workloads.*

### 3. Network Configuration:

- Attach two network adapters to each VM during creation:
   - *NAT Adapter: For internet access, allowing VMs to download necessary packages.*
   - *Host-Only Adapter: For inter-VM communication within the Kubernetes cluster.*

### 4. Hardware Requirements:

- Memory (RAM): At least 2 GB per node (master and worker). For larger workloads, allocate more as needed.
- CPU: At least 2 CPUs per node for a smooth setup and reliable performance.






<br>
<br>

#### ----------Common Step to Follow on Both nodes(Master and Workers node)--------------
### Step 1: Enable Kernel Modules
*Enable the necessary kernel modules for Kubernetes networking.*

```yml

sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system


```

### Step 2: Disable Swap
*Disabling swap is necessary for Kubernetes to function properly.*

```yml

sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

```

### Step 3: Install Containerd Runtime
*Containerd is the recommended container runtime for Kubernetes.*

```yml

sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install containerd.io -y
sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

```



### Step 4: Add Kubernetes Repository
*Add the official Kubernetes repository to install necessary Kubernetes components.*

```yml
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
EOF

sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
sudo systemctl enable --now kubelet


```

<br>



## Master Node Configuration.
#### ---------------*Run the following steps only on the master node.*--------------

### 1. Open Firewall Ports
*Allow necessary ports for the Kubernetes master node.*

```yml
sudo firewall-cmd --permanent --add-port={6443,2379,2380,10250,10251,10252,10257,10259,179}/tcp
sudo firewall-cmd --permanent --add-port=4789/udp
sudo firewall-cmd --reload


```


### 2. Initialize the Cluster

*Initialize the Kubernetes cluster with a specified network CIDR.*

```yml
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=<master_node_IP>

```

*Make sure to add the Master node IP.*

### 3. Configure kubectl Access

```yml
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

```

### 4. Apply Network Add-On

*Use Flannel as the network add-on.*

```yml

kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml


```
*Make sure to copy the token which is generated after this command, (i.e join node command)*



### 5. Generate Join Token (if forgot to copy that time)

*If you did not save the join token, use the following command:*

```yml
kubeadm token create --print-join-command

```


<br>
<br>


#### ---------------Worker Node Configuration--------------------

*Run these commands on each worker node.*

### 1. Open Firewall Ports
*Allow ports for the worker nodes to communicate with the master.*


```yml

sudo firewall-cmd --permanent --add-port={179,10250,30000-32767}/tcp
sudo firewall-cmd --permanent --add-port=4789/udp
sudo firewall-cmd --reload

```

### 2. Join the Cluster

*Use the join command copied from the master node initialization step.*



<br>
<br>
<br>

## Kubernetes Dashboard Setup
*Run on Master node only*

### 1. Deploy Kubernetes Dashboard

```yml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-beta8/aio/deploy/recommended.yaml

```


### 2. Access the Dashboard

*Start the proxy server to access the dashboard*

```yml
kubectl proxy

```

#### *Access it at:*
```yml
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/

```


<br>

### 3. Set Up Authentication for Dashboard.

### 1. Generate Certificates

```yml
grep 'client-certificate-data' ~/.kube/config | head -n 1 | awk '{print $2}' | base64 -d >> kubecfg.crt
grep 'client-key-data' ~/.kube/config | head -n 1 | awk '{print $2}' | base64 -d >> kubecfg.key
openssl pkcs12 -export -clcerts -inkey kubecfg.key -in kubecfg.crt -out kubecfg.p12 -name "kubernetes-client"

```

### 2. Create Service Account and Cluster Role Binding.

```yml

# ServiceAccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dash-admin
  namespace: kube-system

```

<br>

```yml
# ClusterRoleBinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dash-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: dash-admin
  namespace: kube-system

```


*Apply the files:*

```yml
kubectl apply -f ServiceAccount.yaml
kubectl apply -f ClusterRoleBinding.yaml

```


### 3. Generate Access Token

```yml
kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}')

```


### *Copy the token and paste it into the dashboard login prompt.*



<br>
<br>




*After setting up the Kubernetes cluster on Rocky Linux, use the following commands on the master and worker nodes to verify the installation and ensure that the nodes are successfully connected to the cluster.*

### Verification Commands
*On the Master Node*
1.  Check Node Status: Ensure that both master and worker nodes are in a "Ready" state.

```yml
kubectl get nodes

Expected Output: The master node and worker node(s) should be listed with the status "Ready."

```

2. Check Pod Status in All Namespaces: Ensure that essential pods (like kube-dns and network plugin pods) are running.

```yml

kubectl get pods --all-namespaces

Expected Output: All system pods should show the status "Running."
```

3. Verify Cluster Information: This provides an overview of the cluster, including the server and client versions.

```yml
kubectl cluster-info

Expected Output: Information about the Kubernetes API server and other components, indicating successful cluster setup.
```

### On the Worker Node
1. Check kubelet Status: Ensure the kubelet service is active and running on the worker node.

```yml
sudo systemctl status kubelet

Expected Output: The kubelet service should display "active (running)."
```

2. Confirm Node Connection to the Cluster:

- *This step is primarily checked from the master node, as the master confirms that the worker nodes have successfully joined.*
  
- *If you encounter any issues, ensure that the join token command was executed correctly on the worker node.*

##### Upon completing these steps, you will have a fully functional Kubernetes cluster on Rocky Linux, with a master node managing the worker nodes. This setup provides a strong foundation for exploring container orchestration, scaling applications, and managing workloads effectively.
