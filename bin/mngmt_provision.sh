!#/usr/bin/env bash
set -e
####################################################################
# Provision and management CLI commands                            #
####################################################################

#Find the data directory of the etcd daemon
sudo grep data-dir /etc/kubernetes/manifests/etcd.yaml

# etcdctl options
kubectl -n kube-system exec -it etcd-<Tab> -- sh
l#Use TLS and check etcd health
kubectl -n kube-system exec -it etcd-<Tab> -- sh

kubectl -n kube-system exec -it etcd-cp -- sh \
-c "ETCDCTL_API=3 \
ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt \
ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt \
ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key \
etcdctl endpoint health"

#Check etcd databases
kubectl -n kube-system exec -it etcd-cp -- sh \
-c "ETCDCTL_API=3 \
ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt \
ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt \
ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key \
etcdctl --endpoints=https://127.0.0.1:2379 member list -w table"

#Save etcd snapshot
kubectl -n kube-system exec -it etcd-cp -- sh \
-c "ETCDCTL_API=3 \
ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt \
ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt \
ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key \
etcdctl --endpoints=https://127.0.0.1:2379 snapshot save /var/lib/etcd/snapshot.db"

#Backup sensitive information
mkdir $HOME/backup
sudo cp /var/lib/etcd/snapshot_18_01_2024.db $HOME/backup/snapshot.db-$(date +%m-%d-%y)
sudo cp /root/kubeadm-config.yaml $HOME/backup/
sudo cp -r /etc/kubernetes/pki/etcd $HOME/backup/

#Updating k8s Cluster
sudo apt update

sudo apt-cache madison kubeadm #check new version
sudo apt-mark unhold kubeadm
sudo apt install -y kubeadm=1.28.6-1.1 #latest release on the 18 Jan 2024
sudo apt-mark hold kubeadm

#Prepare CP node for update
kubectl drain cp --ignore-daemonsets
sudo kubeadm upgrade plan #check what we will update and how
sudo kubeadm upgrade apply v1.28.6

#Update kubelet
sudo apt-mark unhold kubelet kubectl
sudo apt install -y kubelet=1.28.6-1.1 kubectl=1.28.6-1.1
sudo apt-mark hold kubelet kubectl

#relod and check
sudo systemctl daemon-reload
sudo systemctl restart kubelet
kubectl get node

#make the cp available for the scheduler
kubectl uncordon <name_cp>

#update worker nodes
sudo apt-mark unhold kubeadm
sudo apt-get update && sudo apt-get install -y kubeadm=1.28.6-1.1
sudo apt-mark hold kubeadm

kubectl drain worker --ignore-daemonsets #on CP node!!!!!

sudo kubeadm upgrade node
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.28.6-1.1 kubectl=1.28.6-1.1
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet

kubectl uncordon worker #on CP node!!!!!
kubectl get nodes #All nodes should be updated to the 1.28.6 version

#run stress container for generating load
kubectl create deployment hog --image vish/stress
