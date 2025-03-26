#!/bin/bash

# Kubernetes Easy Installer
# Works on Ubuntu 20.04/22.04
# Supports both master and worker nodes

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
KUBE_VERSION="1.30"
POD_CIDR="192.168.0.0/16"  # Calico default

show_help() {
    echo -e "\n${YELLOW}Usage:${NC}"
    echo "  $0 master    # Setup control plane"
    echo "  $0 worker    # Setup worker node"
    echo -e "\n${YELLOW}Requirements:${NC}"
    echo "  - Ubuntu 20.04/22.04"
    echo "  - Master: 2+ vCPUs, 2GB+ RAM"
    echo "  - Worker: 1+ vCPU, 1GB+ RAM"
    exit 0
}

# Check arguments
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
elif [[ "$1" != "master" && "$1" != "worker" ]]; then
    echo -e "${RED}Error: Specify 'master' or 'worker'${NC}"
    show_help
    exit 1
fi

# Verify Ubuntu
if ! grep -q "Ubuntu" /etc/os-release; then
    echo -e "${RED}Error: Only Ubuntu is supported${NC}"
    exit 1
fi

# Check resources
if [[ "$1" == "master" ]]; then
    if [ $(nproc) -lt 2 ] || [ $(free -m | awk '/Mem:/ {print $2}') -lt 2000 ]; then
        echo -e "${RED}Error: Master requires 2+ vCPUs and 2GB+ RAM${NC}"
        exit 1
    fi
fi

echo -e "\n${GREEN}[1/6] Updating system...${NC}"
sudo apt update -qq
sudo apt upgrade -y -qq

echo -e "\n${GREEN}[2/6] Installing dependencies...${NC}"
sudo apt install -y -qq \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    software-properties-common

echo -e "\n${GREEN}[3/6] Configuring container runtime...${NC}"
# Install Docker
curl -fsSL https://get.docker.com | sudo sh
sudo systemctl enable --now docker

# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd

echo -e "\n${GREEN}[4/6] Installing Kubernetes...${NC}"
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update -qq
sudo apt install -y -qq kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo -e "\n${GREEN}[5/6] Configuring system...${NC}"
# Disable swap
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

# Kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# Network settings
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system >/dev/null

if [[ "$1" == "master" ]]; then
    echo -e "\n${YELLOW}[6/6] Initializing Master...${NC}"
    sudo kubeadm init --pod-network-cidr=${POD_CIDR} --ignore-preflight-errors=Swap
    
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    
    echo -e "\n${GREEN}Installing Calico CNI...${NC}"
    kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
    
    echo -e "\n${YELLOW}✅ Master ready! Use below command to join workers:${NC}"
    kubeadm token create --print-join-command
    echo -e "\nRun this to verify: ${YELLOW}kubectl get nodes${NC}"

else
    echo -e "\n${YELLOW}[6/6] Worker ready for join${NC}"
    echo -e "\nRun on master to get join command:"
    echo -e "${GREEN}kubeadm token create --print-join-command${NC}"
    echo -e "\nThen run that command here"
fi

echo -e "\n${GREEN}✔ Setup complete!${NC}"
