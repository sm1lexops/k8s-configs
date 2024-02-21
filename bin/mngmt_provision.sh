#! /usr/bin/env bash
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

#Explore API calls
export client_cert=$(grep client-cert ~/.kube/config | cut -d " " -f 6)
echo $client_cert
export client_key=$(grep client-key-data ~/.kube/config | cut -d " " -f 6)
echo $client_key
export auth=$(grep certificate-authority-data ~/.kube/config
export auth=$(grep certificate-authority-data ~/.kube/config | cut -d " " -f 6)
echo $auth
echo $client_cert | base64 -d - > ./client.pem
vim client.pem
echo $client_key | base64 -d - > ./client_key.pem
vim client_key.pem
echo $auth | base64 -d - > ./ca.pem
kubectl config view
export srvname=$(grep server ~/.kube/config | -d " " -f 6)
export srvname=$(grep server ~/.kube/config | cut -d " " -f 6)
echo $srvname
curl --cert client.pem --key client_key.pem --cacert ca.pem $srvname/api/v1/pods
vim curlpod.json
curl --cert client.pem --key client_key.pem --cacert ca.pem $srvname/api/v1/namespaces/default/pods -XPOST -H'Content-Type: application/json' -d@curlpod.json


#objects available for v1 api
python3 -m json.tool /home/ubuntu/.kube/cache/discovery/k8scp_6443/apps/v1/serverresources.json | grep kind

python3 -m json.tool /home/ubuntu/.kube/cache/discovery/k8scp_6443/v1/serverresources.json | grep kind
