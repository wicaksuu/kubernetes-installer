#!/bin/bash

set -e

# Function to handle errors
handle_error() {
  echo "Error on line $1"
  echo "Please check the error message above and make sure all commands are executed correctly."
  exit 1
}

# Trap errors and call handle_error
trap 'handle_error $LINENO' ERR

# Check if the script is running on Ubuntu
if [[ "$(lsb_release -is)" != "Ubuntu" ]]; then
  echo "This script is intended to be run on Ubuntu only."
  exit 1
fi

# Get the hostname and use it as the username
USER=$(hostname)

# Ports that need to be checked and cleared
PORTS=(10259 2379 2380 6443 10257)

# Stop services using the specified ports
for PORT in "${PORTS[@]}"; do
  if sudo lsof -ti:$PORT; then
    echo "Stopping service on port $PORT"
    sudo lsof -ti:$PORT | xargs -r sudo kill
  fi
done

# Remove any old versions of Docker
sudo apt-get remove -y docker docker-engine docker.io containerd runc

# Remove Kubernetes components if installed
sudo apt-get remove -y --allow-change-held-packages kubeadm kubectl kubelet kubernetes-cni

# Remove Docker configuration and data
sudo rm -rf /etc/docker /var/lib/docker

# Remove Kubernetes configuration
sudo rm -rf /etc/kubernetes /var/lib/kubernetes

# Remove etcd data
sudo rm -rf /var/lib/etcd/*

# Install Docker dependencies
sudo apt-get update
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker’s official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Set up the Docker stable repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# Enable and start Docker
sudo systemctl enable docker
sudo systemctl start docker

# Add Kubernetes APT repository
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Install Kubernetes components
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Function to initialize Kubernetes master
initialize_kubernetes_master() {
  # Get the public IP address
  PUBLIC_IP=$(curl -s ifconfig.me)

  # Ensure hostname is resolvable
  echo "$PUBLIC_IP $USER" | sudo tee -a /etc/hosts

  # Initialize Kubernetes master with public IP
  sudo kubeadm init --apiserver-advertise-address=$PUBLIC_IP --pod-network-cidr=192.168.0.0/16

  # Configure kubectl for the non-root user
  mkdir -p /home/$USER/.kube
  sudo cp -i /etc/kubernetes/admin.conf /home/$USER/.kube/config
  sudo chown $USER:$USER /home/$USER/.kube/config

  # Deploy Weave Net pod network
  sudo -u $USER kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(sudo -u $USER kubectl version | base64 | tr -d '\n')"

  # Install Kubernetes Dashboard
  sudo -u $USER kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.3.1/aio/deploy/recommended.yaml

  # Create admin user for Kubernetes Dashboard
  cat <<EOF | sudo -u $USER kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF
}

# Try initializing Kubernetes master and check if node is ready
for attempt in {1..3}; do
  echo "Attempt $attempt to initialize Kubernetes master..."
  initialize_kubernetes_master

  echo "Waiting for the node to be ready..."
  for i in {1..20}; do
    NODE_STATUS=$(sudo -u $USER kubectl get nodes --no-headers -o custom-columns=STATUS:.status.conditions[?(@.type=="Ready")].status 2>/dev/null || echo "NotFound")
    echo "Current node status: $NODE_STATUS"
    if [[ $NODE_STATUS == "True" ]]; then
      echo "Node is ready."
      break 2
    elif [[ $i -eq 20 ]]; then
      echo "Node did not become ready in time."
      sudo -u $USER kubectl get nodes
      if [[ $attempt -eq 3 ]]; then
        echo "Node failed to become ready after 3 attempts."
        exit 1
      fi
    else
      echo "Node is not yet ready, waiting for 10 seconds..."
      sleep 10
    fi
  done
done

# Generate join command for worker nodes
JOIN_COMMAND=$(sudo kubeadm token create --print-join-command)

# Create worker setup script
cat <<EOF > setup-worker.sh
#!/bin/bash

set -e

# Function to handle errors
handle_error() {
  echo "Error on line \$1"
  echo "Please check the error message above and make sure all commands are executed correctly."
  exit 1
}

# Trap errors and call handle_error
trap 'handle_error \$LINENO' ERR

# Update and install dependencies
sudo apt-get update && sudo apt-get install -y apt-transport-https curl

# Remove any old versions of Docker
sudo apt-get remove -y docker docker-engine docker.io containerd runc

# Install Docker dependencies
sudo apt-get install -y \
    ca-certificates \
    gnupg \
    lsb-release

# Add Docker’s official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Set up the Docker stable repository
echo \
  "deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  \$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# Enable and start Docker
sudo systemctl enable docker
sudo systemctl start docker

# Add Kubernetes APT repository
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Install Kubernetes components
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Join the Kubernetes cluster
sudo $JOIN_COMMAND
EOF

chmod +x setup-worker.sh

# Output instructions for accessing the dashboard and worker script
echo "Kubernetes master setup is complete."
echo "Run the 'setup-worker.sh' script on each worker node to join the cluster."

# Get the dashboard access token
echo "Kubernetes Dashboard installed."
echo "To access the Kubernetes Dashboard, run 'kubectl proxy' and visit:"
echo "http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
echo "Use the following token to log in:"
sudo -u $USER kubectl -n kubernetes-dashboard create token admin-user
