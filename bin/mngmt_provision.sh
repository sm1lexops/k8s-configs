!#/usr/bin/env bash
set -e
####################################################################
# Provision and management CLI commands                            #
####################################################################

#Find the data directory of the etcd daemon
sudo grep data-dir /etc/kubernetes/manifests/etcd.yaml

# etcdctl options
kubectl -n kube-system exec -it etcd-<Tab> -- sh
