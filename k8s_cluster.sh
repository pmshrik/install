#!/bin/bash

# ==============================================
# Kubernetes Cluster Setup Script
# Version: 2.1
# Author: Your Name
# Description: Sets up a Kubernetes cluster on Ubuntu
# ==============================================

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
KUBE_VERSION="1.30"
POD_CIDR="192.168.0.0/16"  # Default CIDR for Calico

show_help() {
    echo -e "\n${YELLOW}Kubernetes Cluster Setup Script${NC}"
    echo "Usage: sudo $0 [master|worker]"
    echo -e "\n${YELLOW}Options:${NC}"
    echo "  master   - Initialize a control plane node"
    echo "  worker   - Prepare a worker node for joining"
    echo -e "\n${YELLOW}Requirements:${NC}"
    echo "  - Ubuntu 20.04/22.04"
    echo "  - Minimum 2GB RAM for master"
    echo "  - Root privileges"
    exit 0
}

# Validate root access
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root${NC}" >&2
    echo -e "Please run with: ${YELLOW}sudo $0 $@${NC}" >&2
    exit 1
fi

# Argument validation
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
elif [[ "$1" != "master" && "$1" != "worker" ]]; then
    echo -e "${RED}Error: Specify 'master' or 'worker'${NC}" >&2
    show_help
    exit 1
fi

# ==============================================
# Installation Functions
# ==============================================

prepare_system() {
    echo -e "\n${GREEN}[1/6] Preparing system...${NC}"
    apt update -qq
    apt upgrade -y -qq
    apt install -y -qq apt-transport-https ca-certificates curl gnupg
}

setup_container_runtime() {
    echo -e "\n${GREEN}[2/6] Setting up container runtime...${NC}"
    # Install Docker
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker

    # Configure containerd
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl restart containerd
}

install_kubernetes() {
    echo -e "\n${GREEN}[3/6] Installing Kubernetes components...${NC}"
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
    apt update -qq
    apt install -y -qq kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
}

configure_system() {
    echo -e "\n${GREEN}[4/6] Configuring system...${NC}"
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
}

setup_master() {
    echo -e "\n${YELLOW}[5/6] Initializing control plane...${NC}"
    kubeadm init --pod-network-cidr=${POD_CIDR} --ignore-preflight-errors=Swap

    # ==============================================
    # CRITICAL CONFIGURATION: kubectl setup
    # ==============================================
    echo -e "\n${GREEN}[6/6] Configuring kubectl access...${NC}"
    
    # Explanation:
    # 1. Creates the .kube directory if it doesn't exist
    # 2. Copies the admin config to user's home directory
    # 3. Fixes permissions so regular user can use kubectl
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config
    
    echo -e "${YELLOW}✓ kubectl configured for $(whoami) user${NC}"

    # Install network plugin
    echo -e "\n${GREEN}Installing Calico network plugin...${NC}"
    kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

    # Generate join command
    JOIN_CMD=$(kubeadm token create --print-join-command)
    echo -e "\n${YELLOW}✅ Master node ready!${NC}"
    echo -e "\nUse this command to join worker nodes:"
    echo -e "${GREEN}${JOIN_CMD}${NC}"
    
    # Verification
    echo -e "\nCluster status:"
    kubectl get nodes
}

setup_worker() {
    echo -e "\n${YELLOW}[5/6] Worker node ready for joining${NC}"
    echo -e "\nRun this on master to get join command:"
    echo -e "${GREEN}kubeadm token create --print-join-command${NC}"
    echo -e "\nThen run the join command on this worker node."
}

# ==============================================
# Main Execution Flow
# ==============================================

# Run preparation steps
prepare_system
setup_container_runtime
install_kubernetes
configure_system

# Node-specific setup
if [[ "$1" == "master" ]]; then
    setup_master
else
    setup_worker
fi

echo -e "\n${GREEN}✔ Setup completed successfully${NC}"
