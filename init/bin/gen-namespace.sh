#!/bin/bash

set -e

# disable Mingw path mangling on windows
export MSYS_NO_PATHCONV=1

function show_usage() {
    cat <<EOF

Generates YAML files for creating a new namespace, including deployment manifests for Tiller and Flux. This script
creates an 'output' folder with two sub-folders:

  tls: TLS certificates and keys needed to connect to the Tiller server remotely
  yaml: the YAML files containing the deployments for the namespace

usage: gen-namespace.sh --namespace=<namespace> <ARGS>

Prerequisites:

  - openssl must be installed and on the path
  - kubectl must be installed and on the path
  - helm must be installed and on the path
  - kubeseal must be installed and on the path

The following arguments can be specified:
  --country: the (two-letter) country to use when generating TLS certificates
  --flux-version: the version of Flux to install (defaults to master)
  --git-branch: git branch containing deployment information (defaults to master)
  --git-path: path inside the git repository containing deployment information
  --git-url: URL of the git repository containing deployment information
  --helm-domain: common name for the helm server (defaults to helm-<namespace>)
  --help: shows this help message
  --kubeseal-cert: path to the certificate to use for sealing secrets; if not specified, it will be retrieved from the cluster
  --locality: the city or town name to use when generating TLS certificates
  --namespace: the name of the Kubernetes namespace to initialize
  --organization: the organization name to use when generating TLS certificates
  --state: the (full) state to use when generating TLS certificates
  --tiller-domain: common name for the tiller server (defaults to tiller-<namespace>)

EOF
    exit 1
}

function process_arguments() {
    HELP=false
    UNKNOWN_OPTIONS=false
    MISSING_OPTIONS=false

    for i in "$@"
    do
    case $i in
        --namespace=*)
        NAMESPACE="${i#*=}"
        shift # past argument=value
        ;;
        --country=*)
        COUNTRY="${i#*=}"
        shift # past argument=value
        ;;
        --state=*)
        STATE="${i#*=}"
        shift # past argument=value
        ;;
        --locality=*)
        LOCALITY="${i#*=}"
        shift # past argument=value
        ;;
        --organization=*)
        ORGANIZATION="${i#*=}"
        shift # past argument=value
        ;;
        --tiller-domain=*)
        TILLER_DOMAIN="${i#*=}"
        shift # past argument=value
        ;;
        --helm-domain=*)
        HELM_DOMAIN="${i#*=}"
        shift # past argument=value
        ;;
        --flux-version=*)
        FLUX_VERSION="${i#*=}"
        shift # past argument=value
        ;;
        --git-url=*)
        GIT_URL="${i#*=}"
        shift # past argument=value
        ;;
        --git-branch=*)
        GIT_BRANCH="${i#*=}"
        shift # past argument=value
        ;;
        --git-path=*)
        GIT_PATH="${i#*=}"
        shift # past argument=value
        ;;
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

    # default values
    if [[ -z "$FLUX_VERSION" ]]; then
        FLUX_VERSION=master
    fi
    if [[ -z "$GIT_BRANCH" ]]; then
        GIT_BRANCH=master
    fi
    if [[ -z "$TILLER_DOMAIN" ]]; then
        TILLER_DOMAIN=tiller-${NAMESPACE}
    fi
    if [[ -z "$HELM_DOMAIN" ]]; then
        HELM_DOMAIN=helm-${NAMESPACE}
    fi

    if [[ "${HELP}" = "true" ]]; then
        show_usage
    fi

    if [[ -z "$NAMESPACE" ]]; then
        echo "Missing argument: --namespace"
        MISSING_OPTIONS=true
    fi
    if [[ -z "$COUNTRY" ]]; then
        echo "Missing argument: --country"
        MISSING_OPTIONS=true
    fi
    if [[ -z "$STATE" ]]; then
        echo "Missing argument: --state"
        MISSING_OPTIONS=true
    fi
    if [[ -z "$LOCALITY" ]]; then
        echo "Missing argument: --locality"
        MISSING_OPTIONS=true
    fi
    if [[ -z "$ORGANIZATION" ]]; then
        echo "Missing argument: --organization"
        MISSING_OPTIONS=true
    fi
    if [[ -z "$GIT_URL" ]]; then
        echo "Missing argument: --git-url"
        MISSING_OPTIONS=true
    fi
    if [[ -z "$GIT_PATH" ]]; then
        echo "Missing argument: --git-path"
        MISSING_OPTIONS=true
    fi

    if [[ "${UNKNOWN_OPTIONS}" = "true" ]]; then
        show_usage
    fi
    if [[ "${MISSING_OPTIONS}" = "true" ]]; then
        show_usage
    fi
}

function generate_tls_keys() {
    echo Generating TLS keys...

    TILLER_COMMON_NAME=$TILLER_DOMAIN
    HELM_COMMON_NAME=$HELM_DOMAIN

    # generate tiller certs
    mkdir -p output/tls
    openssl genrsa -out output/tls/ca.key.pem 4096
    openssl req -key output/tls/ca.key.pem -new -x509 -days 7300 -sha256 -out output/tls/ca.cert.pem -extensions v3_ca -nodes -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/CN=$TILLER_COMMON_NAME"

    openssl genrsa -out output/tls/tiller.key.pem 4096
    openssl genrsa -out output/tls/helm.key.pem 4096

    openssl req -key output/tls/tiller.key.pem -new -sha256 -out output/tls/tiller.csr.pem -nodes -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/CN=$TILLER_COMMON_NAME"
    openssl req -key output/tls/helm.key.pem -new -sha256 -out output/tls/helm.csr.pem  -nodes -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/CN=$HELM_COMMON_NAME"

    openssl x509 -req -CA output/tls/ca.cert.pem -CAkey output/tls/ca.key.pem -CAcreateserial -in output/tls/tiller.csr.pem -out output/tls/tiller.cert.pem -days 3650
    openssl x509 -req -CA output/tls/ca.cert.pem -CAkey output/tls/ca.key.pem -CAcreateserial -in output/tls/helm.csr.pem -out output/tls/helm.cert.pem  -days 3650
}

function generate_templated_yaml() {
    echo Generating templated yaml files...

    CA_CONTENT=`awk 'NF {sub(/\r/, ""); printf "%s\\\\n",$0;}' output/tls/ca.cert.pem`

    mkdir -p output/yaml/tiller
    cp templates/namespace/*.yaml output/yaml
    cp templates/namespace/tiller/*.yaml output/yaml/tiller


    find output/yaml -name *.yaml -exec sed -i -e "s/\${NAMESPACE}/${NAMESPACE}/" \{\} \;
    find output/yaml -name *.yaml -exec sed -i -e "s,\${GIT_URL},${GIT_URL}," \{\} \;
    find output/yaml -name *.yaml -exec sed -i -e "s,\${GIT_PATH},${GIT_PATH}," \{\} \;
    find output/yaml -name *.yaml -exec sed -i -e "s,\${CA_CONTENT},${CA_CONTENT}," \{\} \;
}

function generate_helm_yaml() {
    echo Generating yaml files from Helm charts...

    rm -rf output/tmp
    mkdir -p output/tmp/helm
    mkdir -p output/tmp/output
    git clone https://github.com/weaveworks/flux.git output/tmp/flux -b ${FLUX_VERSION}

    helm template -n flux-${NAMESPACE} \
        --namespace ${NAMESPACE} \
        --output-dir output/tmp/helm \
        --set git.url=${GIT_URL} \
        --set git.path=${GIT_PATH} \
        --set git.pollInterval=1m \
        --set registry.pollInterval=1m \
        --set helmOperator.create=true \
        --set helmOperator.createCRD=false \
        --set helmOperator.allowNamespace=${NAMESPACE} \
        --set helmOperator.tillerNamespace=${NAMESPACE} \
        --set helmOperator.git.pollInterval=3m \
        --set helmOperator.tls.enable=true \
        --set helmOperator.tls.verify=true \
        --set helmOperator.tls.caContent="$(cat output/tls/ca.cert.pem)" \
        --set helmOperator.tls.hostname=tiller-${NAMESPACE} \
        --set prometheus.enabled=true \
        --set rbac.create=false \
        --set serviceAccount.create=false \
        --set serviceAccount.name=flux-${NAMESPACE} \
        output/tmp/flux/chart/flux

    find output/tmp/helm/flux/templates -name *.yaml -exec sed \{\} -i -e "/^\  name: .*/ a\
\  namespace: ${NAMESPACE}" \;

    mkdir -p output/yaml/flux
    cp output/tmp/helm/flux/templates/*.yaml output/yaml/flux
    rm -rf output/tmp
}

function generate_secrets() {
    echo Generating secrets...

    if [[ ! -z "${KUBESEAL_CERT}" ]]; then
        mkdir -p output/tmp
        cp ${KUBESEAL_CERT} output/tmp/kubeseal-cert.pem
        KUBESEAL_ARGS="--cert output/tmp/kubeseal-cert.pem"
    fi

    mkdir -p output/yaml/secrets

    kubectl create secret generic tiller-secret \
        -n ${NAMESPACE} \
        --dry-run=true \
        -o yaml \
        --from-file=ca.crt=output/tls/ca.cert.pem \
        --from-file=tls.crt=output/tls/tiller.cert.pem \
        --from-file=tls.key=output/tls/tiller.key.pem \
        | kubeseal --format yaml ${KUBESEAL_ARGS} \
        > output/yaml/secrets/tiller-secret.yaml

    kubectl create secret generic helm-client-certs \
        -n ${NAMESPACE} \
        --dry-run=true \
        -o yaml \
        --from-file=tls.crt=output/tls/helm.cert.pem \
        --from-file=tls.key=output/tls/helm.key.pem \
        | kubeseal --format yaml ${KUBESEAL_ARGS} \
        > output/yaml/secrets/helm-client-certs.yaml
}

process_arguments $@

rm -rf output
mkdir output
generate_tls_keys
generate_templated_yaml
generate_helm_yaml
generate_secrets
