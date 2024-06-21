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