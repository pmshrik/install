#!/bin/bash

# Kubernetes Easy Installer
# For Ubuntu 20.04/22.04 - No Interactive Dialogs
# Supports master/worker setup

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Config
KUBE_VERSION="1.30"
POD_CIDR="192.168.0.0/16"

# Prevent interactive dialogs
export DEBIAN_FRONTEND=noninteractive

show_help() {
    echo -e "\n${YELLOW}Usage:${NC}"
    echo "  sudo $0 master    # Setup control plane"
    echo "  sudo $0 worker    # Setup worker node"
    exit 0
}

# Verify root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Run with sudo${NC}"
    exit 1
fi

# Check args
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
elif [[ "$1" != "master" && "$1" != "worker" ]]; then
    echo -e "${RED}Specify 'master' or 'worker'${NC}"
    show_help
    exit 1
fi

echo -e "\n${GREEN}[1/6] Updating system...${NC}"
apt-get update -qq
apt-get upgrade -y -qq

echo -e "\n${GREEN}[2/6] Installing dependencies...${NC}"
apt-get install -y -qq \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    needrestart

# Configure automatic restart handling
echo -e "\n${GREEN}[3/6] Setting up container runtime...${NC}"
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker

# Configure containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

# Auto-handle service restarts
sudo needrestart -r a -q

echo -e "\n${GREEN}[4/6] Installing Kubernetes...${NC}"
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
apt-get update -qq
apt-get install -y -qq kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

echo -e "\n${GREEN}[5/6] Configuring system...${NC}"
# Disable swap
swapoff -a
sed -i '/swap/d' /etc/fstab

# Load kernel modules
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# Network settings
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system >/dev/null

if [[ "$1" == "master" ]]; then
    echo -e "\n${YELLOW}[6/6] Initializing Master...${NC}"
    kubeadm init --pod-network-cidr=${POD_CIDR} --ignore-preflight-errors=Swap
    
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config
    
    echo -e "\n${GREEN}Installing Calico...${NC}"
    kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
    
    echo -e "\n${YELLOW}✅ Master ready! Use below to join workers:${NC}"
    kubeadm token create --print-join-command

else
    echo -e "\n${YELLOW}[6/6] Worker ready for join${NC}"
    echo -e "\nRun on master:"
    echo -e "${GREEN}kubeadm token create --print-join-command${NC}"
fi

# Final cleanup
sudo needrestart -r a -q
echo -e "\n${GREEN}✔ Done!${NC}"
