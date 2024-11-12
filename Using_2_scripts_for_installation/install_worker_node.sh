#!/bin/bash

echo "######### Kubernetes Worker Node Setup ###########"

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

# Step 5: Open Firewall Ports for Worker Node
echo "Configuring firewall for worker node..."
sudo firewall-cmd --permanent --add-port={179,10250,30000-32767}/tcp
sudo firewall-cmd --permanent --add-port=4789/udp
sudo firewall-cmd --reload

# Step 6: Join the Kubernetes Cluster
read -p "Enter the join command from the master node: " join_command
$join_command

echo "######## Worker Node Setup Completed ########"
