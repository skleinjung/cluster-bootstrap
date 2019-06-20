#!/bin/bash

kubectl delete deployment -n kube-system tiller-deploy
kubectl delete service -n kube-system tiller-deploy
kubectl delete secret -n kube-system helm-client-certs
kubectl delete secret -n kube-system tiller-secret

kubectl delete service -n kube-system flux-master
kubectl delete service -n kube-system flux-master-memcached
kubectl delete deployment -n kube-system flux-master
kubectl delete deployment -n kube-system flux-master-memcached
kubectl delete deployment -n kube-system flux-master-helm-operator
kubectl delete serviceaccount -n kube-system flux-master
kubectl delete clusterrole flux-master
kubectl delete clusterrolebinding flux-master
