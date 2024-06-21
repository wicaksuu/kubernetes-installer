#!/bin/bash

set -e  # Memastikan script berhenti jika ada kesalahan

# Memperbarui daftar paket dan menginstal docker
sudo apt update
sudo apt install docker.io -y

# Menghentikan dan menonaktifkan apparmor, lalu me-restart containerd
sudo systemctl stop apparmor && sudo systemctl disable apparmor

# Mengaktifkan dan memulai layanan docker
sudo systemctl enable docker
sudo systemctl start docker

# Menambahkan kunci GPG untuk repositori Kubernetes
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Menambahkan repositori Kubernetes ke daftar sumber APT
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg arch=amd64] https://pkgs.k8s.io/core:/stable:/v1.30/deb/amd64 stable main' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Memperbarui daftar paket setelah menambahkan repositori baru dan menginstal kubelet, kubeadm, dan kubectl
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Menonaktifkan swap dan mengomentari baris swap di fstab
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/' /etc/fstab