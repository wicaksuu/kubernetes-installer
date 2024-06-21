#!/bin/bash

set -e  # Memastikan script berhenti jika ada kesalahan


sudo apt update

sudo systemctl stop apparmor && sudo systemctl disable apparmor
sudo systemctl restart containerd.service

sudo apt install docker.io -y

sudo systemctl enable docker

sudo systemctl start docker

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg arch=amd64] https://pkgs.k8s.io/core:/stable:/v1.30/deb/amd64 stable main' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update

sudo apt install -y kubelet kubeadm kubectl

sudo apt-mark hold kubelet kubeadm kubectl

sudo swapoff -a

sudo sed -i '/ swap / s/^\(.*\)$/#\1/' /etc/fstab

sudo nano /etc/modules-load.d/containerd.conf
echo "overlay" >> /etc/modules-load.d/containerd.conf
echo "br_netfilter" >> /etc/modules-load.d/containerd.conf

sudo modprobe overlay
sudo modprobe br_netfilter

sudo nano /etc/sysctl.d/kubernetes.conf
echo "net.bridge.bridge-nf-call-ip6tables = 1" >> /etc/sysctl.d/kubernetes.conf
echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.d/kubernetes.conf
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/kubernetes.conf

sudo sysctl --system

sudo nano /etc/default/kubelet
echo 'KUBELET_EXTRA_ARGS="--cgroup-driver=cgroupfs"' >> /etc/default/kubelet
sudo systemctl daemon-reload && sudo systemctl restart kubelet

sudo nano /etc/docker/daemon.json
echo '{ "exec-opts": ["native.cgroupdriver=systemd"],"log-driver": "json-file","log-opts": {"max-size": "100m"},"storage-driver": "overlay2" }' >> /etc/docker/daemon.json
sudo systemctl daemon-reload && sudo systemctl restart docker

sudo kubeadm init --control-plane-endpoint="$1" --upload-certs

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config


kubectl get nodes