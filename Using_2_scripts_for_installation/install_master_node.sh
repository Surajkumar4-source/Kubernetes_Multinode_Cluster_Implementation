#!/bin/bash

echo "######### Kubernetes Master Node Setup ###########"

# Step 1: Enable Kernel Modules
echo "Enabling necessary kernel modules..."
sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# Apply sysctl parameters
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system

# Step 2: Disable Swap
echo "Disabling swap..."
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

# Step 3: Install Containerd Runtime
echo "Installing containerd runtime..."
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install containerd.io -y
sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Step 4: Add Kubernetes Repository and Install Components
echo "Adding Kubernetes repository and installing components..."
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

# Step 5: Open Firewall Ports for Master Node
echo "Configuring firewall for master node..."
sudo firewall-cmd --permanent --add-port={6443,2379,2380,10250,10251,10252,10257,10259,179}/tcp
sudo firewall-cmd --permanent --add-port=4789/udp
sudo firewall-cmd --reload

# Step 6: Initialize Kubernetes Cluster
echo "Initializing Kubernetes cluster..."
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=<master_node_IP>

# Step 7: Configure kubectl for Cluster Admin
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Step 8: Apply Network Add-On
echo "Applying network add-on..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Display Join Command for Worker Nodes
echo "######### Copy the following join command to connect worker nodes #########"
kubeadm token create --print-join-command

# Optional: Install Kubernetes Dashboard
read -p "Do you want to install the Kubernetes Dashboard? (y/n): " install_dashboard
if [ "$install_dashboard" == "y" ]; then
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-beta8/aio/deploy/recommended.yaml
    echo "Dashboard available at: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
    echo "Run 'kubectl proxy' to access the dashboard."
fi

echo "######## Master Node Setup Completed ########"
