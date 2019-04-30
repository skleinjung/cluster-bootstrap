#!/usr/bin/env bash

#Required
tiller_domain=tiller-server
tiller_commonname=$tiller_domain
helm_domain=helm-client
helm_commonname=$helm_domain

#Change to your company details
country=US
state=Minnesota
locality=Eagan
organization=Thrashplay
organizationalunit=
email=

# apply bootstrap k8s objects
kubectl apply -f bootstrap

# generate system-wide tiller certs
mkdir -p tls/bootstrap
openssl genrsa -out tls/bootstrap/ca.key.pem 4096
openssl req -key tls/bootstrap/ca.key.pem -new -x509 -days 7300 -sha256 -out tls/bootstrap/ca.cert.pem -extensions v3_ca -nodes -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$tiller_commonname/emailAddress=$email"

openssl genrsa -out tls/bootstrap/tiller.key.pem 4096
openssl genrsa -out tls/bootstrap/helm.key.pem 4096

openssl req -key tls/bootstrap/tiller.key.pem -new -sha256 -out tls/bootstrap/tiller.csr.pem -nodes -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$tiller_commonname/emailAddress=$email"
openssl req -key tls/bootstrap/helm.key.pem -new -sha256 -out tls/bootstrap/helm.csr.pem  -nodes -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$helm_commonname/emailAddress=$email"

openssl x509 -req -CA tls/bootstrap/ca.cert.pem -CAkey tls/bootstrap/ca.key.pem -CAcreateserial -in tls/bootstrap/tiller.csr.pem -out tls/bootstrap/tiller.cert.pem -days 3650
openssl x509 -req -CA tls/bootstrap/ca.cert.pem -CAkey tls/bootstrap/ca.key.pem -CAcreateserial -in tls/bootstrap/helm.csr.pem -out tls/bootstrap/helm.cert.pem  -days 3650

# deploy helm client secrets
go get github.com/bitnami-labs/sealed-secrets/cmd/kubeseal
kubectl create secret tls helm-client-certs \
    -n kube-system \
    --dry-run \
    --cert=tls/bootstrap/helm.cert.pem \
    --key=tls/bootstrap/helm.key.pem \
    --output yaml \
    | kubeseal --format yaml > tls/bootstrap/sealed-helm-client-certs.yaml
kubectl apply -f tls/bootstrap/sealed-helm-client-certs.yaml

# deploy helm
mkdir -p helm
curl -o helm/get_helm.sh -L https://git.io/get_helm.sh
chmod 700 helm/get_helm.sh
helm/get_helm.sh

# initialize tiller
helm init --tiller-tls \
    --service-account tiller-bootstrap \
    --tiller-tls-cert tls/bootstrap/tiller.cert.pem \
    --tiller-tls-key tls/bootstrap/tiller.key.pem \
    --tiller-tls-verify \
    --tls-ca-cert tls/bootstrap/ca.cert.pem \
    --override 'spec.template.spec.containers[0].command'='{/tiller,--storage=secret}'
kubectl rollout status -w deployment/tiller-deploy --namespace=kube-system

# deploy flux
helm repo add weaveworks https://weaveworks.github.io/flux
kubectl apply -f https://raw.githubusercontent.com/weaveworks/flux/master/deploy-helm/flux-helm-release-crd.yaml

helm upgrade -i flux --namespace kube-system \
    --set git.url=git@github.com:skleinjung/thrashplay-deployment \
    --set git.path=deployments \
    --set git.pollInterval=1m \
    --set registry.pollInterval=1m \
    --set helmOperator.create=true \
    --set helmOperator.createCRD=false \
    --set helmOperator.git.pollInterval=3m \
    --set helmOperator.tls.enable=true \
    --set helmOperator.tls.verify=true \
    --set helmOperator.tls.caContent="$(cat tls/bootstrap/ca.cert.pem)" \
    --set prometheus.enabled=true \
    weaveworks/flux

rm -rf helm