#!/bin/bash

set -e  # Exit on error

# -------------------------------
# CONFIGURATION VARIABLES
# -------------------------------
KUBERNETES_VERSION="1.29"
POD_NETWORK_CIDR="192.168.0.0/16"
MASTER_IP="192.168.1.100"  # Change this to match your master node's IP

# Detect if the current node is the Master or Worker
if [[ "$HOSTNAME" == "master-node" ]]; then
    IS_MASTER=true
else
    IS_MASTER=false
fi

# -------------------------------
# STEP 1: Update & Upgrade System
# -------------------------------
echo ">>> Updating system..."
sudo apt update && sudo apt upgrade -y

# -------------------------------
# STEP 2: Disable Swap
# -------------------------------
echo ">>> Disabling swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# -------------------------------
# STEP 3: Load Kernel Modules
# -------------------------------
echo ">>> Loading kernel modules..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# -------------------------------
# STEP 4: Install Container Runtime (Containerd)
# -------------------------------
echo ">>> Installing containerd..."
sudo apt install -y containerd

# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Restart containerd
sudo systemctl restart containerd
sudo systemctl enable containerd

# -------------------------------
# STEP 5: Install Kubernetes Components
# -------------------------------
echo ">>> Installing Kubernetes components..."
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl

# Add Kubernetes repository
curl -fsSL https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION/deb/Release.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/kubernetes.gpg

echo "deb https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo systemctl enable kubelet

# -------------------------------
# STEP 6: Kubernetes Setup (Master Node)
# -------------------------------
if [ "$IS_MASTER" = true ]; then
    echo ">>> Initializing Kubernetes on Master Node..."
    
    sudo kubeadm init --pod-network-cidr=$POD_NETWORK_CIDR
    
    echo ">>> Configuring kubectl for Master..."
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    echo ">>> Deploying Calico network..."
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26/manifests/calico.yaml
    
    echo ">>> Kubernetes Master Node setup is complete!"
    
    echo ">>> Run the following command on Worker Nodes:"
    kubeadm token create --print-join-command
    
else
    # -------------------------------
    # STEP 7: Kubernetes Setup (Worker Node)
    # -------------------------------
    echo ">>> Waiting for Master Node setup..."
    sleep 10
    
    echo ">>> Joining Kubernetes cluster as Worker Node..."
    JOIN_COMMAND=$(ssh ubuntu@$MASTER_IP "kubeadm token create --print-join-command")
    sudo $JOIN_COMMAND
    
    echo ">>> Worker Node setup is complete!"
fi
