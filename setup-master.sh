#!/bin/bash

set -e  # Memastikan script berhenti jika ada kesalahan

# Fungsi untuk mengecek port yang sedang digunakan dan menghentikan proses yang menggunakan port itu
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

# Fungsi untuk membersihkan direktori /var/lib/etcd jika tidak kosong
cleanup_etcd_directory() {
    local etcd_dir="/var/lib/etcd"

    echo "Cleaning up $etcd_dir..."

    # Periksa apakah direktori kosong
    if [ "$(ls -A $etcd_dir)" ]; then
        echo "$etcd_dir is not empty. Stopping etcd service and clearing contents..."
        
        # Hentikan layanan etcd jika sedang berjalan
        sudo systemctl stop etcd || true  # Gunakan '|| true' untuk melanjutkan jika perintah gagal
        
        # Hapus isi dari direktori etcd
        sudo rm -rf $etcd_dir/* || { echo "Failed to clean up $etcd_dir. Exiting."; exit 1; }
    fi
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
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg || { echo "Failed to add Kubernetes repository key. Exiting."; exit 1; }
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list || { echo "Failed to add Kubernetes repository to sources list. Exiting."; exit 1; }

    # Install paket Kubernetes
    sudo apt-get update || { echo "Failed to update package list. Exiting."; exit 1; }
    sudo apt-get install -y kubeadm kubelet kubectl || { echo "Failed to install Kubernetes components. Exiting."; exit 1; }

    # Inisialisasi cluster Kubernetes
    sudo kubeadm init --apiserver-advertise-address=$PUBLIC_IP --pod-network-cidr=10.244.0.0/16 || { echo "Failed to initialize Kubernetes cluster. Exiting."; exit 1; }

    # Setelah berhasil, atur konfigurasi kubectl untuk pengguna non-root
    mkdir -p $HOME/.kube || { echo "Failed to create .kube directory. Exiting."; exit 1; }
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config || { echo "Failed to copy Kubernetes config file. Exiting."; exit 1; }
    sudo chown $(id -u):$(id -g) $HOME/.kube/config || { echo "Failed to change ownership of Kubernetes config file. Exiting."; exit 1; }

    # Instalasi Calico sebagai plugin jaringan untuk Kubernetes
    kubectl apply -f https://docs.projectcalico.org/v3.14/manifests/calico.yaml || { echo "Failed to apply Calico network plugin. Exiting."; exit 1; }

    # Instalasi Kubernetes Dashboard
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.4.0/aio/deploy/recommended.yaml || { echo "Failed to apply Kubernetes Dashboard. Exiting."; exit 1; }

    # Membuat ServiceAccount dan ClusterRoleBinding untuk Dashboard
    kubectl create serviceaccount dashboard-admin-sa || { echo "Failed to create Dashboard ServiceAccount. Exiting."; exit 1; }
    kubectl create clusterrolebinding dashboard-admin-sa --clusterrole=cluster-admin --serviceaccount=default:dashboard-admin-sa || { echo "Failed to create Dashboard ClusterRoleBinding. Exiting."; exit 1; }

    # Tampilkan token untuk login ke Dashboard
    echo "Kubernetes master installation completed successfully."
    echo "Save the following token for Kubernetes Dashboard access:"
    kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep dashboard-admin-sa-token | awk '{print $1}') || { echo "Failed to get Dashboard token. Exiting."; exit 1; }

    # Tampilkan perintah untuk proxy kubectl
    echo "To access Kubernetes Dashboard, run the following command in your terminal:"
    echo "kubectl proxy --address=0.0.0.0 --accept-hosts='^.*$' &"
}

# Main script
cleanup_etcd_directory  # Bersihkan /var/lib/etcd jika tidak kosong
check_port_availability  # Periksa ketersediaan port sebelum instalasi
get_public_ip  # Dapatkan IP publik dari sistem

# Install Kubernetes di master node
install_kubernetes_master

echo "Kubernetes installation completed successfully."
