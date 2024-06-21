chmod +x setup-master.sh
./setup-master.sh

https://phoenixnap.com/kb/install-kubernetes-on-ubuntu

Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
https://kubernetes.io/docs/concepts/cluster-administration/addons/

You can now join any number of the control-plane node running the following command on each as root:

kubeadm join kube-master:6443 --token ywn9wk.4z544v9t55nqltbf \
 --discovery-token-ca-cert-hash sha256:30704727692350ca470324d27cbb2dcb060aa201313fccda89fc2596f97a50c4 \
 --control-plane --certificate-key 65900a05d8645fb10c22def01d28e09ceb0fc593f7c4338acd36f5e2c809667c

Please note that the certificate-key gives access to cluster sensitive data, keep it secret!
As a safeguard, uploaded-certs will be deleted in two hours; If necessary, you can use
"kubeadm init phase upload-certs --upload-certs" to reload certs afterward.

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join kube-master:6443 --token ywn9wk.4z544v9t55nqltbf \
 --discovery-token-ca-cert-hash sha256:30704727692350ca470324d27cbb2dcb060aa201313fccda89fc2596f97a50c4

admin-user
eyJhbGciOiJSUzI1NiIsImtpZCI6IjJrNWR4WmZ5aVJxTncxMkRJQmdFLXY4a2ZKQkw5RUFMbGpfU3R2LVpycjQifQ.eyJhdWQiOlsiaHR0cHM6Ly9rdWJlcm5ldGVzLmRlZmF1bHQuc3ZjLmNsdXN0ZXIubG9jYWwiXSwiZXhwIjoxNzE4OTYxNDA4LCJpYXQiOjE3MTg5NTc4MDgsImlzcyI6Imh0dHBzOi8va3ViZXJuZXRlcy5kZWZhdWx0LnN2Yy5jbHVzdGVyLmxvY2FsIiwianRpIjoiMmI0N2I4YmEtZGEyZS00MjNjLTlmMGUtMTkwMGVkMTVmMTJmIiwia3ViZXJuZXRlcy5pbyI6eyJuYW1lc3BhY2UiOiJrdWJlcm5ldGVzLWRhc2hib2FyZCIsInNlcnZpY2VhY2NvdW50Ijp7Im5hbWUiOiJhZG1pbi11c2VyIiwidWlkIjoiNTM4ZmFlYmUtYzQ3MS00NDgxLWIwMDAtNTBjNDA4Njc0NDY4In19LCJuYmYiOjE3MTg5NTc4MDgsInN1YiI6InN5c3RlbTpzZXJ2aWNlYWNjb3VudDprdWJlcm5ldGVzLWRhc2hib2FyZDphZG1pbi11c2VyIn0.qwFzFXQFtVw6HWhJZKZoYO3dwVQFZxRgZyFsCP_NxY8IKWU3HOuFIrNQdWptNkdJet5Hq6kVuLu8Na7jU21dTdrPlaT2Pom4XC0yRYUM6mBIHfqefGLRaKPmHCtERgONnKwCkot5oEix8C8Innnv-oB2kH_Z70tzWPC7QodBp3NPOAh-hA3FOlOh4ffJ6KN_u6-RJ9BQYsls182DX-R6k0OxIioZBJvgLiL6lZyy5_fNk0Ud-DGHXlk6Qql2Zwh5QTYl9I6vpu1_OcQtBD4tCjThzw6FZx3nlRBBUYnWIz0t_ku7bcRmGPocg7dPv9oKhzhV18nnm3wXJMeRfLXDxA
