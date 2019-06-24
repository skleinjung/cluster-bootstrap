#!/bin/bash

set -e

# disable Mingw path mangling on windows
export MSYS_NO_PATHCONV=1

function show_usage() {
    cat <<EOF

Generates YAML file containing a secret suitable for use as a Git deploy key for flux. This secret will be encrypted
using the SealedSecrets controller deployed in the cluster. The following directory will be created with the specified
contents:

  tls: the deploy key to configure in your git server
  yaml: the YAML files containing the secret deployments

usage: init-flux-master-deploy-key.sh

Prerequisites:
  - Bitnami SealedSecrets must be deployed to the cluster and running

The following arguments can be specified:
  --kubeseal-cert: path to the certificate to use for sealing secrets; if not specified, it will be retrieved from the cluster
EOF
    exit 1
}

function process_arguments() {
    HELP=false
    UNKNOWN_OPTIONS=false

    for i in "$@"
    do
    case $i in
        --kubeseal-cert=*)
        KUBESEAL_CERT="${i#*=}"
        shift # past argument=value
        ;;
        --help)
        HELP=true
        shift
        ;;
        *)
        UNKNOWN_OPTIONS=true
        echo Unknown option: ${i}
        shift
        ;;
    esac
    done

    if [[ "${HELP}" = "true" ]]; then
        show_usage
    fi
    if [[ "${UNKNOWN_OPTIONS}" = "true" ]]; then
        show_usage
    fi
}

process_arguments

rm -rf output

echo Generating ssh key...

# generate tiller certs
mkdir -p output/keys
ssh-keygen -f output/keys/flux-deploy-key -t rsa -b 4096 -N ""

# encrypt cert
if [[ ! -z "${KUBESEAL_CERT}" ]]; then
    mkdir -p output/tmp
    cp ${KUBESEAL_CERT} output/tmp/kubeseal-cert.pem
    KUBESEAL_ARGS="--cert output/tmp/kubeseal-cert.pem"
fi

mkdir -p output/yaml/secrets

kubectl create secret generic flux-master-deploy-key \
    -n flux-master \
    --dry-run=true \
    -o yaml \
    --from-file=identity=output/keys/flux-deploy-key \
    | kubeseal --format yaml ${KUBESEAL_ARGS} \
    > output/yaml/secrets/03-flux-master-deploy-key.yaml
