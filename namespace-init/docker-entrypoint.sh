#!/bin/bash
set -e

function var_usage() {
    cat <<EOF
The following environment variables determine what namespace to initialize:
  NAMESPACE: the Kubernetes namespace to initialize

The following environment variables are required to generate TLS certificates:
  COUNTRY: two-letter country code
  STATE: full state name
  LOCALITY: city or town name
  ORGANIZATION: organization name

The following environment variables are optionally used to generated TLS certificates:
  TILLER_DOMAIN: common name for tiller server (defaults to tiller-server)
  HELM_DOMAIN: common name for helm client (defaults to helm-client)

The following environment variables are required to configure Flux:
  GIT_URL: URL of the git repository to manage for deployments
  GIT_PATH: path inside the git repository containing deployment information
EOF
    exit 1
}

# check required environment variables are set
[[ -z "$NAMESPACE" ]] && var_usage

[[ -z "$COUNTRY" ]] && var_usage
[[ -z "$STATE" ]] && var_usage
[[ -z "$LOCALITY" ]] && var_usage
[[ -z "$ORGANIZATION" ]] && var_usage

[[ -z "$GIT_URL" ]] && var_usage
[[ -z "$GIT_PATH" ]] && var_usage

echo Downloading helm...
if [[ ! -z ${HELM_VERSION} ]]
then
    get_helm.sh -v ${HELM_VERSION}
else
    get_helm.sh
fi

echo Generating TLS keys...
# default values
if [[ -z "$TILLER_DOMAIN" ]]; then
    TILLER_DOMAIN=tiller-server
fi
if [[ -z "$HELM_DOMAIN" ]]; then
    HELM_DOMAIN=helm-client
fi

TILLER_COMMON_NAME=$TILLER_DOMAIN
HELM_COMMON_NAME=$HELM_DOMAIN

# generate system-wide tiller certs
mkdir -p /tls
openssl genrsa -out /tls/ca.key.pem 4096
openssl req -key /tls/ca.key.pem -new -x509 -days 7300 -sha256 -out /tls/ca.cert.pem -extensions v3_ca -nodes -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/CN=$TILLER_COMMON_NAME   "

openssl genrsa -out /tls/tiller.key.pem 4096
openssl genrsa -out /tls/helm.key.pem 4096

openssl req -key /tls/tiller.key.pem -new -sha256 -out /tls/tiller.csr.pem -nodes -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/CN=$TILLER_COMMON_NAME"
openssl req -key /tls/helm.key.pem -new -sha256 -out /tls/helm.csr.pem  -nodes -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/CN=$HELM_COMMON_NAME"

openssl x509 -req -CA /tls/ca.cert.pem -CAkey /tls/ca.key.pem -CAcreateserial -in /tls/tiller.csr.pem -out /tls/tiller.cert.pem -days 3650
openssl x509 -req -CA /tls/ca.cert.pem -CAkey /tls/ca.key.pem -CAcreateserial -in /tls/helm.csr.pem -out /tls/helm.cert.pem  -days 3650

echo Creating namespace...
kubectl create namespace ${NAMESPACE}

echo Initialize access controls....
kubectl create serviceaccount -n ${NAMESPACE} tiller-${NAMESPACE}

echo Initializing Tiller...
helm init --tiller-tls \
    --service-account tiller-${NAMESPACE} \
    --tiller-namespace ${NAMESPACE} \
    --tiller-tls-cert /tls/tiller.cert.pem \
    --tiller-tls-key /tls/tiller.key.pem \
    --tiller-tls-verify \
    --tls-ca-cert /tls/ca.cert.pem \
    --override 'spec.template.spec.containers[0].command'='{/tiller,--storage=secret}'
kubectl rollout status -w deployment/tiller-deploy --namespace=${NAMESPACE}

echo Installing Helm secrets...
kubectl create secret tls helm-client-certs \
    -n ${NAMESPACE} \
    --cert=tls/helm.cert.pem \
    --key=tls/helm.key.pem

echo Installing Flux...
helm repo add weaveworks https://weaveworks.github.io/flux
kubectl apply -f https://raw.githubusercontent.com/weaveworks/flux/master/deploy-helm/flux-helm-release-crd.yaml

helm upgrade -i flux-bootstrap --namespace ${NAMESPACE} \
    --tls --tls-verify --tls-hostname $TILLER_COMMON_NAME --tls-ca-cert /tls/ca.cert.pem --tls-cert /tls/helm.cert.pem --tls-key /tls/helm.key.pem \
    --set git.url=${GIT_URL} \
    --set git.path=${GIT_PATH} \
    --set git.pollInterval=1m \
    --set registry.pollInterval=1m \
    --set helmOperator.create=true \
    --set helmOperator.createCRD=false \
    --set helmOperator.git.pollInterval=3m \
    --set helmOperator.tls.enable=true \
    --set helmOperator.tls.verify=true \
    --set helmOperator.tls.caContent="$(cat /tls/ca.cert.pem)" \
    --set prometheus.enabled=true \
    weaveworks/flux

echo CA Cert:
cat /tls/ca.cert.pem

if [[ "$LOG_KEYS" = "true" ]]; then
    echo Helm Cert:
    cat /tls/helm.cert.pem

    echo Helm Key:
    cat /tls/helm.key.pem
fi
