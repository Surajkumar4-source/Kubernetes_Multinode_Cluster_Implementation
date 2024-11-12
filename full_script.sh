#!/bin/bash

echo "######### Kubernetes Cluster Installation ###########"
echo "#### Common Installation Script for Manager and Worker Nodes ####"
sleep 2

# Step 1: Enable Kernel Modules
echo "Enabling necessary kernel modules for networking..."

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
echo "Kernel modules and sysctl parameters applied."

# Step 2: Disable Swap
echo "Disabling swap..."
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab
echo "Swap disabled."

# Step 3: Install Containerd Runtime
echo "Installing containerd runtime..."
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install containerd.io -y
sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd
echo "Containerd runtime installed and configured."

# Step 4: Add Kubernetes Repository
echo "Adding Kubernetes repository..."
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
EOF

# Install Kubernetes components
sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
sudo systemctl enable --now kubelet
echo "Kubernetes components installed."

# Instructions for Master Node
if [[ $(hostnamectl | grep "master") ]]; then
    echo "########## Master Node Configuration ##########"
    
    # Step 5: Open Firewall Ports on Master Node
    echo "Opening firewall ports for master node..."
    sudo firewall-cmd --permanent --add-port={6443,2379,2380,10250,10251,10252,10257,10259,179}/tcp
    sudo firewall-cmd --permanent --add-port=4789/udp
    sudo firewall-cmd --reload

    # Step 6: Initialize Kubernetes Cluster
    echo "Initializing Kubernetes cluster on master node..."
    sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=<master_node_IP>
    
    # Step 7: Configure kubectl for Cluster Admin
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    # Step 8: Apply Network Add-On
    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
    echo "Master node initialization completed. Copy the join command for worker nodes."

    # Step 9: Display Join Token
    echo "If you forgot the join token, generate it with this command:"
    echo "kubeadm token create --print-join-command"
fi

# Instructions for Worker Node
if [[ $(hostnamectl | grep "worker") ]]; then
    echo "########## Worker Node Configuration ##########"

    # Open firewall ports for Worker Node
    echo "Opening firewall ports for worker node..."
    sudo firewall-cmd --permanent --add-port={179,10250,30000-32767}/tcp
    sudo firewall-cmd --permanent --add-port=4789/udp
    sudo firewall-cmd --reload
    echo "Firewall ports opened on worker node."

    echo "Run the join command provided by the master node to join the cluster."
fi

# Optional: Install Kubernetes Dashboard on Master Node
if [[ $(hostnamectl | grep "master") ]]; then
    echo "########## Installing Kubernetes Dashboard ##########"
    
    # Deploy Dashboard
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-beta8/aio/deploy/recommended.yaml
    kubectl proxy &

    echo "Dashboard available at: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
    echo "To access the dashboard, set up authentication as follows:"

    # Generate certificates for access
    grep 'client-certificate-data' ~/.kube/config | head -n 1 | awk '{print $2}' | base64 -d >> kubecfg.crt
    grep 'client-key-data' ~/.kube/config | head -n 1 | awk '{print $2}' | base64 -d >> kubecfg.key
    openssl pkcs12 -export -clcerts -inkey kubecfg.key -in kubecfg.crt -out kubecfg.p12 -name "kubernetes-client"

    # Create Service Account and Cluster Role Binding
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dash-admin
  namespace: kube-system
EOF

    cat <<EOF | kubectl apply -f -
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
EOF

    # Display Access Token
    echo "Use the following command to retrieve your dashboard login token:"
    echo "kubectl -n kube-system describe secret \$(kubectl -n kube-system get secret | grep dash-admin | awk '{print \$1}')"
    echo "Copy the token and paste it into the Kubernetes Dashboard login page."
fi

echo "######## Kubernetes Cluster Installation Script Completed ########"
