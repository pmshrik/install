#!/bin/bash

# Variables
MASTER_IP="192.168.1.10"  # Replace with your master node's IP
POD_NETWORK_CIDR="192.168.0.0/16"
KUBE_VERSION="1.28.0"     # Replace with your desired Kubernetes version
CONTAINER_RUNTIME=""      # Will be set to "docker" or "containerd"

# Function to initialize the master node
init_master() {
    echo "Initializing Kubernetes master node..."

    # Initialize the cluster
    sudo kubeadm init --pod-network-cidr=$POD_NETWORK_CIDR --kubernetes-version=$KUBE_VERSION

    # Set up kubeconfig for the current user
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    # Install Calico CNI plugin
    echo "Installing Calico CNI plugin..."
    kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

    # Install kubectx and kubens
    echo "Installing kubectx and kubens..."
    sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
    sudo ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
    sudo ln -s /opt/kubectx/kubens /usr/local/bin/kubens

    # Generate the join command for worker nodes
    JOIN_COMMAND=$(kubeadm token create --print-join-command)
    echo "Join command for worker nodes:"
    echo "sudo $JOIN_COMMAND"
}

# Function to join worker nodes
join_worker() {
    echo "Joining Kubernetes worker node..."

    # Replace with the actual join command from the master node
    JOIN_COMMAND="sudo kubeadm join $MASTER_IP:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
    echo "Running join command: $JOIN_COMMAND"
    eval $JOIN_COMMAND
}

# Function to install dependencies
install_dependencies() {
    echo "Installing dependencies..."

    # Update system
    sudo apt update && sudo apt upgrade -y

    # Install required packages
    sudo apt install -y curl apt-transport-https ca-certificates software-properties-common git

    # Disable swap
    sudo swapoff -a
    sudo sed -i '/swap/d' /etc/fstab

    # Install Docker and containerd
    echo "Installing Docker and containerd..."
    sudo apt install -y docker.io containerd.io

    # Configure Docker to use systemd as the cgroup driver
    if [[ $CONTAINER_RUNTIME == "docker" ]]; then
        echo "Configuring Docker as the container runtime..."
        sudo mkdir -p /etc/docker
        cat <<EOF | sudo tee /etc/docker/daemon.json
        {
          "exec-opts": ["native.cgroupdriver=systemd"],
          "log-driver": "json-file",
          "log-opts": {
            "max-size": "100m"
          },
          "storage-driver": "overlay2"
        }
        EOF
        sudo systemctl daemon-reload
        sudo systemctl restart docker
        sudo systemctl enable docker
    fi

    # Configure containerd
    if [[ $CONTAINER_RUNTIME == "containerd" ]]; then
        echo "Configuring containerd as the container runtime..."
        sudo mkdir -p /etc/containerd
        sudo containerd config default | sudo tee /etc/containerd/config.toml
        sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
        sudo systemctl restart containerd
        sudo systemctl enable containerd
    fi

    # Add Kubernetes repository
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
    sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"

    # Install Kubernetes components
    sudo apt update
    sudo apt install -y kubelet=$KUBE_VERSION-00 kubeadm=$KUBE_VERSION-00 kubectl=$KUBE_VERSION-00
    sudo apt-mark hold kubelet kubeadm kubectl
}

# Main script
echo "Kubernetes Cluster Setup Script"

# Prompt user to choose container runtime
echo "Choose the container runtime:"
echo "1. Docker"
echo "2. containerd"
read -p "Enter your choice (1 or 2): " runtime_choice

if [[ $runtime_choice == 1 ]]; then
    CONTAINER_RUNTIME="docker"
elif [[ $runtime_choice == 2 ]]; then
    CONTAINER_RUNTIME="containerd"
else
    echo "Invalid choice. Exiting."
    exit 1
fi

# Check if the script is running on the master or worker node
if [[ $1 == "master" ]]; then
    echo "Setting up master node..."
    install_dependencies
    init_master
elif [[ $1 == "worker" ]]; then
    echo "Setting up worker node..."
    install_dependencies
    join_worker
else
    echo "Usage: $0 [master|worker]"
    exit 1
fi

echo "Setup completed!"
