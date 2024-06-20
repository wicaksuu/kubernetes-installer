#!/bin/bash

set -e  # Memastikan script berhenti jika ada kesalahan

# Fungsi untuk menunggu perintah sampai berhasil atau mencapai timeout
wait_until_success() {
    local cmd="$1"
    local retries=5
    local wait_seconds=10
    local count=0

    until $cmd || [ $count -eq $retries ]; do
        echo "Waiting for the command to succeed..."
        sleep $wait_seconds
        ((count++))
    done

    if [ $count -eq $retries ]; then
        echo "Command failed after $retries retries. Exiting."
        exit 1
    fi
}

# Fungsi untuk membersihkan instalasi Kubernetes sebelumnya
cleanup_kubernetes() {
    echo "Cleaning up previous Kubernetes installation..."

    # Hentikan semua layanan Kubernetes yang berjalan
    sudo systemctl stop kubelet
    sudo systemctl stop docker

    # Hapus semua paket Kubernetes
    sudo apt-get purge -y kubeadm kubelet kubectl kubernetes-cni kube* docker.io

    # Hapus konfigurasi Kubernetes dan direktori lainnya
    sudo rm -rf ~/.kube /etc/kubernetes /var/lib/dockershim /var/lib/cni /var/lib/kubelet /var/log/containers /var/log/pods
}

# Fungsi untuk mengecek port yang sedang digunakan
check_port_availability() {
    local ports=(6443 2379 2380 10250 10251 10252 10255)

    echo "Checking port availability..."

    for port in "${ports[@]}"; do
        if sudo lsof -i:$port -sTCP:LISTEN -t >/dev/null; then
            echo "Port $port is already in use. Exiting."
            exit 1
        fi
    done
}

# Fungsi untuk mendapatkan IP publik dari sistem
get_public_ip() {
    # Menggunakan layanan eksternal untuk mendapatkan IP publik
    # Misalnya, menggunakan ifconfig.me
    public_ip=$(curl -s ifconfig.me/ip)
    echo "Detected public IP address: $public_ip"
    export PUBLIC_IP=$public_ip
}

# Fungsi untuk instalasi Kubernetes di master node
install_kubernetes_master() {
    echo "Installing Kubernetes on master node..."

    # Tambahkan repository Kubernetes
    sudo apt-get update
    sudo apt-get install -y apt-transport-https curl
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

    # Install paket Kubernetes
    sudo apt-get update
    sudo apt-get install -y kubeadm kubelet kubectl

    # Inisialisasi cluster Kubernetes
    sudo kubeadm init --apiserver-advertise-address=$PUBLIC_IP --pod-network-cidr=10.244.0.0/16

    # Setelah berhasil, atur konfigurasi kubectl untuk pengguna non-root
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    # Tambahkan Calico sebagai network plugin
    kubectl apply -f https://docs.projectcalico.org/v3.14/manifests/calico.yaml

    # Instalasi Kubernetes Dashboard
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.4.0/aio/deploy/recommended.yaml

    # Membuat ServiceAccount dan ClusterRoleBinding untuk Dashboard
    kubectl create serviceaccount dashboard-admin-sa
    kubectl create clusterrolebinding dashboard-admin-sa --clusterrole=cluster-admin --serviceaccount=default:dashboard-admin-sa

    # Tampilkan token untuk login ke Dashboard
    echo "Kubernetes master installation completed successfully."
    echo "Save the following token for Kubernetes Dashboard access:"
    kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep dashboard-admin-sa-token | awk '{print $1}')

    # Tampilkan perintah untuk proxy kubectl
    echo "To access Kubernetes Dashboard, run the following command in your terminal:"
    echo "kubectl proxy --address=0.0.0.0 --accept-hosts='^.*$' &"
}

# Main script
cleanup_kubernetes  # Bersihkan instalasi sebelumnya jika ada
check_port_availability  # Periksa ketersediaan port sebelum instalasi
get_public_ip  # Dapatkan IP publik dari sistem

# Install Kubernetes di master node
install_kubernetes_master

echo "Kubernetes installation completed successfully."
