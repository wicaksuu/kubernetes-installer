#!/bin/bash

set -e  # Stop script on any error

# Function to check if a port is in use and kill the related process
check_port_availability() {
    local ports=(6443 2379 2380 10250 10251 10252 10255)

    echo "Checking port availability..."

    for port in "${ports[@]}"; do
        if sudo lsof -i:$port -sTCP:LISTEN -t >/dev/null; then
            echo "Port $port is already in use. Killing related process..."
            sudo kill -9 $(sudo lsof -t -i:$port)
        fi
    done
}

# Function to clean up /var/lib/etcd directory if not empty
cleanup_etcd_directory() {
    local etcd_dir="/var/lib/etcd"

    echo "Cleaning up $etcd_dir..."

    # Check if directory is not empty
    if [ "$(ls -A $etcd_dir)" ]; then
        echo "$etcd_dir is not empty. Stopping etcd service and clearing contents..."
        
        # Stop etcd service if running
        sudo systemctl stop etcd || true  # Use '|| true' to continue if command fails
        
        # Remove contents of etcd directory
        sudo rm -rf $etcd_dir/* || { echo "Failed to clean up $etcd_dir. Exiting."; exit 1; }
    fi
}

# Function to get public IP address of the system
get_public_ip() {
    # Using an external service to get public IP
    # Example: using ifconfig.me
    public_ip=$(curl -s ifconfig.me/ip)
    echo "Detected public IP address: $public_ip"
    export PUBLIC_IP=$public_ip
}

# Function to install Kubernetes on master node
install_kubernetes_master() {
    echo "Installing Kubernetes on master node..."

    # Add Kubernetes repository key
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg || { echo "Failed to add Kubernetes repository key. Exiting."; exit 1; }

    # Add Kubernetes repository to sources list
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list || { echo "Failed to add Kubernetes repository to sources list. Exiting."; exit 1; }

    # Install Kubernetes components
    sudo apt-get update || { echo "Failed to update package list. Exiting."; exit 1; }
    sudo apt-get install -y kubeadm kubelet kubectl || { echo "Failed to install Kubernetes components. Exiting."; exit 1; }

    # Initialize Kubernetes cluster
    sudo kubeadm init --apiserver-advertise-address=$PUBLIC_IP --pod-network-cidr=10.244.0.0/16 || { echo "Failed to initialize Kubernetes cluster. Exiting."; exit 1; }

    # After successful init, configure kubectl for non-root user
    mkdir -p $HOME/.kube || { echo "Failed to create .kube directory. Exiting."; exit 1; }
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config || { echo "Failed to copy Kubernetes config file. Exiting."; exit 1; }
    sudo chown $(id -u):$(id -g) $HOME/.kube/config || { echo "Failed to change ownership of Kubernetes config file. Exiting."; exit 1; }

    # Install Calico network plugin
    kubectl apply -f https://docs.projectcalico.org/v3.14/manifests/calico.yaml || { echo "Failed to apply Calico network plugin. Exiting."; exit 1; }

    # Install Kubernetes Dashboard
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.4.0/aio/deploy/recommended.yaml || { echo "Failed to apply Kubernetes Dashboard. Exiting."; exit 1; }

    # Create ServiceAccount and ClusterRoleBinding for Dashboard
    kubectl create serviceaccount dashboard-admin-sa || { echo "Failed to create Dashboard ServiceAccount. Exiting."; exit 1; }
    kubectl create clusterrolebinding dashboard-admin-sa --clusterrole=cluster-admin --serviceaccount=default:dashboard-admin-sa || { echo "Failed to create Dashboard ClusterRoleBinding. Exiting."; exit 1; }

    # Display token for Dashboard access
    echo "Kubernetes master installation completed successfully."
    echo "Save the following token for Kubernetes Dashboard access:"
    kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep dashboard-admin-sa-token | awk '{print $1}') || { echo "Failed to get Dashboard token. Exiting."; exit 1; }

    # Display kubectl proxy command
    echo "To access Kubernetes Dashboard, run the following command in your terminal:"
    echo "kubectl proxy --address=0.0.0.0 --accept-hosts='^.*$' &"
}

# Main script
cleanup_etcd_directory  # Clean up /var/lib/etcd if not empty
check_port_availability  # Check port availability before installation
get_public_ip  # Get public IP address of the system

# Install Kubernetes on master node
install_kubernetes_master

echo "Kubernetes installation completed successfully."
