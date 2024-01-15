! #/usr/bin/env bash
set -e
# update for deb 20.04 - 22.04 versions tested
sudo apt update -y
sudo apt upgrade -y

sudo apt install -y apt-transport-https ca-certificates curl gpg \
apt-transport-https vim git wget software-properties-common lsb-release ca-certificates
sudo swapoff -a
modprobe overlay
modprobe br_netfilter
#Download the public signing key for the Kubernetes package repositories
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/kubernetes-apt-keyring.gpg

#Add k8s packages source list
echo 'deb [signed-by=/etc/apt/trusted.gpg.d/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
LOCAL_IP=$(hostname -I | awk '{print $1}')
sudo cat <<EOF | sudo tee -a /etc/hosts
$LOCAL_IP k8scp
EOF

#Install container runtime, choose for your best fit containerd/CRI-O/cir-dockerd
sudo apt install -y containerd
sudo systemctl daemon-reload
sudo systemctl enable --now containerd

sudo mkdir -p /etc/containerd
sudo touch config.toml
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd

#Update and install k8s
sudo vim /etc/kubernetes/kubeadm-config.yaml
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

#The kubelet is now restarting every few seconds, as it waits in a crashloop for kubeadm to tell it what to do.

#Configure a CRI cgroup driver

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

#Check packet filtering running
lsmod | grep br_netfilter
lsmod | grep overlay
#Check network routing
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward

# Install k8s cluster
sudo cat <<EOF | sudo tee /etc/kubernetes/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: 1.28.5
controlPlaneEndpoint: "k8scp:6443"
networking:
  podSubnet: 172.22.0.0/16
EOF 
#sudo kubeadm init --control-plane-endpoint #If you have plans to upgrade this single control-plane kubeadm cluster to high availability
sudo kubeadm init --config=/etc/kubernetes/kubeadm-config.yaml --upload-certs | tee kubeadm-init.out

#To make run kubectl fron non-root user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

#Installing a Pod network add-on
#I using cilium
#helm repo add cilium https://helm.cilium.io/$ helm repo update$ helm template cilium cilium/cilium --version 1.14.1 \--namespace kube-system > cilium.yaml
#remote copy with pub key 
scp -i /path/to/.pem /path/to/file <remote_address>:/home/ubuntu/lfsconfigs

kubectl apply -f /home/student/LFS258/SOLUTIONS/s_03/cilium-cni.yaml
#bash completion for kubectl
sudo apt install bash-completion -y
exit #log back in
source <(kubectl completion bash)
echo "source <(kubectl completion bash)" >> $HOME/.bashrc

#Generate token for joining worker nodes and ca cert hash summ 
sudo kubeadm token create --print-join-command | tee kubeadm-join.out
openssl x509 -pubkey \
-in /etc/kubernetes/pki/ca.crt | openssl rsa \
-pubin -outform der 2>/dev/null | openssl dgst \
-sha256 -hex | sed 's/ˆ.* //'

#Join your worker nodes to the cluster
kubeadm join \
--token 27eee4.6e66ff60318da929 \
k8scp:6443 \
--discovery-token-ca-cert-hash \
sha256:6d541678b05652e1fa5d43908e75e67376e994c3483d6683f2a18673e5d2a1b0