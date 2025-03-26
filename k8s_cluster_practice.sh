#!/bin/bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function show_help() {
    echo -e "\n${YELLOW}Kubernetes Cluster Installer${NC}"
    echo "Usage: $0 [master|worker]"
    echo -e "\n${YELLOW}Requirements:${NC}"
    echo "  - Ubuntu 20.04/22.04"
    echo "  - Master: 2+ vCPUs, 2GB+ RAM"
    echo "  - Worker: 1+ vCPU, 1GB+ RAM"
    exit 0
}

# Argument check
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
elif [[ "$1" != "master" && "$1" != "worker" ]]; then
    echo -e "${RED}Error: Use 'master' or 'worker'${NC}"
    show_help
    exit 1
fi

# Verify Ubuntu
if ! grep -q "Ubuntu" /etc/os-release; then
    echo -e "${RED}Error: Only Ubuntu is supported${NC}"
    exit 1
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

# Disable swap
echo -e "\n${GREEN}[3/6] Disabling swap...${NC}"
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

# Install Docker
echo -e "\n${GREEN}[4/6] Installing Docker...${NC}"
curl -fsSL https://get.docker.com | sudo sh
sudo systemctl enable --now docker

# Install containerd
echo -e "\n${GREEN}[5/6] Installing containerd...${NC}"
sudo apt install -y -qq containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd

# Install Kubernetes
echo -e "\n${GREEN}[6/6] Installing Kubernetes...${NC}"
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update -qq
sudo apt install -y -qq kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Master setup
if [[ "$1" == "master" ]]; then
    echo -e "\n${YELLOW}Initializing Master Node...${NC}"
    sudo kubeadm init --pod-network-cidr=192.168.0.0/16
    
    echo -e "\n${GREEN}Setting up kubeconfig...${NC}"
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    
    echo -e "\n${GREEN}Installing Calico CNI...${NC}"
    kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
    
    echo -e "\n${YELLOW}✅ Master setup complete!${NC}"
    echo -e "\nRun this command on worker nodes:"
    echo -e "${GREEN}kubeadm token create --print-join-command${NC}"

# Worker setup
else
    echo -e "\n${YELLOW}Worker Node Ready${NC}"
    echo -e "\nRun on master to get join command:"
    echo -e "${GREEN}kubeadm token create --print-join-command${NC}"
    echo -e "\nThen run the command here"
fi

echo -e "\n${GREEN}Done!${NC}"
