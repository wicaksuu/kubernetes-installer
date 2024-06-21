#!/bin/bash

set -e  # Memastikan script berhenti jika ada kesalahan

# Memperbarui paket dan menginstal Docker
sudo apt update
sudo apt install docker.io -y

# Menghentikan dan menonaktifkan AppArmor
sudo systemctl stop apparmor && sudo systemctl disable apparmor

# Mengaktifkan dan memulai Docker
sudo systemctl enable docker
sudo systemctl start docker

# Menambahkan kunci GPG untuk repositori Kubernetes
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Menambahkan repositori Kubernetes
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg arch=amd64] https://pkgs.k8s.io/core:/stable:/v1.30/deb/amd64 stable main' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Memperbarui paket setelah menambahkan repositori baru
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Menonaktifkan swap
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/' /etc/fstab

# Mengonfigurasi modul untuk containerd
sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

# Memuat modul kernel
sudo modprobe overlay
sudo modprobe br_netfilter

# Mengonfigurasi sysctl untuk Kubernetes
sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

# Mengonfigurasi kubelet
echo 'KUBELET_EXTRA_ARGS="--cgroup-driver=cgroupfs"' | sudo tee /etc/default/kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Mengonfigurasi Docker daemon
sudo tee /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {"max-size": "100m"},
  "storage-driver": "overlay2"
}
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker

# Restart containerd
sudo systemctl restart containerd.service

# Inisialisasi Kubernetes
sudo kubeadm init --control-plane-endpoint="$1" --upload-certs

# Mengonfigurasi kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Menampilkan node
kubectl get nodes