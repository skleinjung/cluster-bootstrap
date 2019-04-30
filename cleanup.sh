#!/bin/bash

kubectl delete deployment -n kube-system tiller-deploy
kubectl delete service -n kube-system tiller-deploy
kubectl delete secret -n kube-system helm-client-certs
kubectl delete secret -n kube-system tiller-secret

kubectl delete service -n kube-system flux-bootstrap
kubectl delete service -n kube-system flux-bootstrap-memcached
kubectl delete deployment -n kube-system flux-bootstrap
kubectl delete deployment -n kube-system flux-bootstrap-memcached
kubectl delete deployment -n kube-system flux-bootstrap-helm-operator
kubectl delete serviceaccount -n kube-system flux-bootstrap
kubectl delete clusterrole flux-bootstrap
kubectl delete clusterrolebinding flux-bootstrap
