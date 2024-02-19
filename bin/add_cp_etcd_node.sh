! #/usr/bin/env bash
####################################################################
# Deploying k8s Cluster                                            #
####################################################################

set -e
# update for deb 20.04 - 22.04 versions tested
sudo apt update -y
sudo apt upgrade -y

#Rename node to k8scp and worker
cat <<EOF | sudo tee /etc/hostname
<your_hostname>
EOF

sudo hostnamectl set-hostname <your_hostname>

LOCAL_IP=$(hostname -I | awk '{print $1}')
sudo cat <<EOF | sudo tee -a /etc/hosts
$LOCAL_IP <your_hostname>
EOF
sudo reboot

sudo apt install -y apt-transport-https ca-certificates curl gpg \
apt-transport-https vim git wget software-properties-common lsb-release ca-certificates
sudo swapoff -a
sudo modprobe overlay
sudo modprobe br_netfilter
#Download the public signing key for the Kubernetes package repositories
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/kubernetes-apt-keyring.gpg

#Add k8s packages source list
echo 'deb [signed-by=/etc/apt/trusted.gpg.d/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

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

sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

#The kubelet is now restarting every few seconds, as it waits in a crashloop for kubeadm to tell it what to do.

#Configure a CRI cgroup driver

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

# If you have error message sysctl: setting key "net.ipv4.conf.all.promote_secondaries": Invalid argument
# Change this parameter
sudo sysctl -w net.ipv4.conf.all.promote_secondaries=1
sysctl net.ipv4.conf.all.promote_secondaries

#Check packet filtering running
lsmod | grep br_netfilter
lsmod | grep overlay
#Check network routing
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward

# Edit the/etc/hosts file ON ALL NODES to ensure the alias of k8scp,
# cp-nodes and etc is set on each node to the proxy IP  address.Your IP address may be different.
# Check all inbound and outbond Firewall rules between cp nodes, if you have some errors

cat <<EOF | sudo tee -a /etc/hosts
10.10.10.xx k8scp
10.10.10.xx cp-node-1
10.10.10.xx cp-node-2
EOF

# Create token and generate new SSL hash on MAIN k8s Cluster Control Plain 
CPTOKEN=$(sudo kubeadm token create)
CPHASH=$(openssl x509 -pubkey \
-in /etc/kubernetes/pki/ca.crt | openssl rsa \
-pubin -outform der 2>/dev/null | openssl dgst \
-sha256 -hex | sed 's/^,* //')

# Create a new cp cert to join as a cp instead of as a worker
CPCERTKEY=$(sudo kubeadm init phase upload-certs --upload-certs)

# Run on second CP nodes to add it to the k8s cluster
sudo kubeadm join k8scp:6443 --token $CPTOKEN --discovery-token-ca-cert-hash sha256:$CPHASH --control-plane --certificate-key $CPCERTKEY

# For administration on this second cp node, add execute next line

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# If cp node is not added, reset node and clear configurations
sudo kubeadm reset
sudo rm -fR /etc/cni/net.d
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X

# Check etcd db state
kubectl -n kubu-system get pods | grep etcd
kubectl -n kube-system exec -it etcd-<cp-node-1> -- /bin/sh
# then in **ETCDCTL_API**
etcdctl -w table \
--endpoints 10.10.xx.xx.:2379,172.xx.xx.xx:2379 \
--cacert /etc/kubernetes/pki/etcd/ca.crt \
--cert /etc/kubernetes/pki/etcd/server.crt \
--key /etc/kubernetes/pki/etcd/server.key \
endpoint status

