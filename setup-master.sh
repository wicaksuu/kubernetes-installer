#!/bin/bash

set -e  # Memastikan script berhenti jika ada kesalahan

# Fungsi untuk mengecek port yang sedang digunakan dan menghentikan proses yang menggunakan port itu
check_port_availability() {
    local ports=(6443 2379 2380 10250 10251 10252 10255 10257 10259)

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
        echo "$etcd_dir is not empty. Clearing contents..."
        
        # Hapus isi dari direktori etcd
        sudo rm -rf $etcd_dir/* || { echo "Failed to clean up $etcd_dir. Exiting."; exit 1; }
    fi
}

# Fungsi untuk membersihkan file-file Kubernetes yang sudah ada
cleanup_kubernetes_manifests() {
    local manifests_dir="/etc/kubernetes/manifests"

    echo "Cleaning up $manifests_dir..."

    # Hapus file-file manifests Kubernetes yang ada
    sudo rm -f $manifests_dir/kube-apiserver.yaml
    sudo rm -f $manifests_dir/kube-controller-manager.yaml
    sudo rm -f $manifests_dir/kube-scheduler.yaml
    sudo rm -f $manifests_dir/etcd.yaml
}

# Fungsi untuk mendapatkan IP publik dari sistem
get_public_ip() {
    public_ip=$(curl -s ifconfig.me/ip)
    echo "Detected public IP address: $public_ip"
    export PUBLIC_IP=$public_ip
}

# Fungsi untuk instalasi Kubernetes di master node
install_kubernetes_master() {
    echo "Installing Kubernetes on master node..."

    if [ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]; then
        curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg || { echo "Failed to add Kubernetes repository key. Exiting."; exit 1; }
        echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list || { echo "Failed to add Kubernetes repository to sources list. Exiting."; exit 1; }
    fi

    sudo apt-get update || { echo "Failed to update package list. Exiting."; exit 1; }

    sudo apt-get install -y kubeadm kubelet kubectl || { echo "Failed to install Kubernetes components. Exiting."; exit 1; }

    if ! sudo kubeadm init --apiserver-advertise-address=$PUBLIC_IP --pod-network-cidr=10.244.0.0/16; then
        echo "Retrying kubeadm init to address CoreDNS issue..."
        sleep 10
        sudo kubeadm init --apiserver-advertise-address=$PUBLIC_IP --pod-network-cidr=10.244.0.0/16 || { echo "Failed to initialize Kubernetes cluster after retry. Exiting."; exit 1; }
    fi

    configure_kubectl_for_non_root

    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.24.0/manifests/calico.yaml || { echo "Failed to apply Calico network plugin. Exiting."; exit 1; }

    kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.4.0/aio/deploy/recommended.yaml || { echo "Failed to apply Kubernetes Dashboard. Exiting."; exit 1; }

    kubectl create serviceaccount dashboard-admin-sa || { echo "Failed to create Dashboard ServiceAccount. Exiting."; exit 1; }
    kubectl create clusterrolebinding dashboard-admin-sa --clusterrole=cluster-admin --serviceaccount=default:dashboard-admin-sa || { echo "Failed to create Dashboard ClusterRoleBinding. Exiting."; exit 1; }

    # Ubah Service Kubernetes Dashboard ke NodePort
    kubectl -n kubernetes-dashboard edit service kubernetes-dashboard <<EOF
spec:
  type: NodePort
  ports:
    - port: 443
      targetPort: 8443
      nodePort: 30000
EOF

    echo "Kubernetes master installation completed successfully."
    save_dashboard_token
    create_worker_join_script
    create_summary_file
    echo "Rekapitulasi telah disimpan di data.txt"
}

# Fungsi untuk mengonfigurasi kubectl untuk pengguna non-root
configure_kubectl_for_non_root() {
    echo "Configuring kubectl for non-root user..."

    mkdir -p $HOME/.kube || { echo "Failed to create .kube directory. Exiting."; exit 1; }
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config || { echo "Failed to copy Kubernetes config file. Exiting."; exit 1; }
    sudo chown $(id -u):$(id -g) $HOME/.kube/config || { echo "Failed to change ownership of Kubernetes config file. Exiting."; exit 1; }
}

# Fungsi untuk menyimpan token dashboard ke file data.txt
save_dashboard_token() {
    echo "Save the following token for Kubernetes Dashboard access:" > data.txt
    kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep dashboard-admin-sa-token | awk '{print $1}') >> data.txt || { echo "Failed to get Dashboard token. Exiting."; exit 1; }
    echo "" >> data.txt
    echo "To access Kubernetes Dashboard, open the following URL in your browser:" >> data.txt
    echo "https://$PUBLIC_IP:30000" >> data.txt
}

# Fungsi untuk membuat file bash untuk worker node
create_worker_join_script() {
    join_command=$(kubeadm token create --print-join-command)
    echo "#!/bin/bash" > join-worker.sh
    echo "set -e" >> join-worker.sh
    echo "check_port_availability() {" >> join-worker.sh
    echo "  local ports=(6443 2379 2380 10250 10251 10252 10255 10257 10259)" >> join-worker.sh
    echo "  echo 'Checking port availability...'" >> join-worker.sh
    echo "  for port in \"\${ports[@]}\"; do" >> join-worker.sh
    echo "    if sudo lsof -i:\$port -sTCP:LISTEN -t >/dev/null; then" >> join-worker.sh
    echo "      echo 'Port \$port is already in use. Killing related process...'" >> join-worker.sh
    echo "      sudo kill -9 \$(sudo lsof -t -i:\$port)" >> join-worker.sh
    echo "    fi" >> join-worker.sh
    echo "  done" >> join-worker.sh
    echo "}" >> join-worker.sh
    echo "check_port_availability" >> join-worker.sh
    echo "$join_command" >> join-worker.sh
    chmod +x join-worker.sh
    echo "Worker node join script created: join-worker.sh"
    echo "" >> data.txt
    echo "Worker node join script:" >> data.txt
    echo "$join_command" >> data.txt
}

# Fungsi untuk membuat file rekapitulasi
create_summary_file() {
    echo "Kubernetes installation completed successfully." >> data.txt
    echo "Summary of important information:" >> data.txt
    echo "Public IP Address: $PUBLIC_IP" >> data.txt
    echo "" >> data.txt
    echo "Kubernetes Dashboard URL:" >> data.txt
    echo "https://$PUBLIC_IP:30000" >> data.txt
    echo "" >> data.txt
    echo "Run the following command to start the proxy:" >> data.txt
    echo "kubectl proxy --address=0.0.0.0 --accept-hosts='^.*$' &" >> data.txt
    echo "" >> data.txt
    echo "Worker node join script command:" >> data.txt
    echo "$(cat join-worker.sh)" >> data.txt
}

# Main script
cleanup_etcd_directory  # Bersihkan /var/lib/etcd jika tidak kosong
check_port_availability  # Periksa ketersediaan port sebelum instalasi
cleanup_kubernetes_manifests  # Bersihkan file-file manifests Kubernetes yang ada
get_public_ip  # Dapatkan IP publik dari sistem

install_kubernetes_master  # Install Kubernetes di master node

echo "Kubernetes installation completed successfully."
