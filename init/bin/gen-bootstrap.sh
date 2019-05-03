#!/bin/bash

set -e

# disable Mingw path mangling on windows
export MSYS_NO_PATHCONV=1

function show_usage() {
    cat <<EOF

Generates YAML files for initializing a new cluster's bootstrap Flux deployment. This script
creates an 'output' folder with one sub-folder:

  yaml: the YAML files containing the deployments for the namespace

usage: gen-bootstrap.sh <ARGS>

Prerequisites:

  - helm must be installed and on the path

The following arguments can be specified:
  --flux-version: the version of Flux to install (defaults to master)
  --git-branch: GIT branch containing deployment information (defaults to master)
  --git-path: path inside the git repository containing deployment information
  --git-url: URL of the git repository containing deployment information
  --help: shows this help message

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
        shift
        ;;
        --git-path=*)
        GIT_PATH="${i#*=}"
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

    if [[ "${HELP}" = "true" ]]; then
        show_usage
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

function generate_templated_yaml() {
    echo Generating templated yaml files...

    mkdir -p output/yaml
    cp templates/cluster/*.yaml output/yaml

    find output/yaml -name *.yaml -exec sed -i -e "s,\${GIT_URL},${GIT_URL}," \{\} \;
    find output/yaml -name *.yaml -exec sed -i -e "s,\${GIT_BRANCH},${GIT_BRANCH}," \{\} \;
    find output/yaml -name *.yaml -exec sed -i -e "s,\${GIT_PATH},${GIT_PATH}," \{\} \;
}

function generate_flux_yaml() {
    echo Generating Flux files from Helm charts...

    rm -rf output/tmp
    mkdir -p output/tmp/charts
    mkdir -p output/tmp/gen

    helm repo add weaveworks https://weaveworks.github.io/flux
    helm fetch --untar --untardir output/tmp/charts 'weaveworks/flux'

    helm template -n flux-master \
        --namespace kube-system \
        --output-dir output/tmp/gen \
        --set git.url=${GIT_URL} \
        --set git.branch=${GIT_BRANCH} \
        --set git.path=${GIT_PATH} \
        --set git.pollInterval=1m \
        --set registry.pollInterval=1m \
        --set helmOperator.create=false \
        --set prometheus.enabled=true \
        --set rbac.create=false \
        --set serviceAccount.create=false \
        --set serviceAccount.name=flux-master \
        output/tmp/charts/flux

    find output/tmp/gen/flux/templates -name *.yaml -exec sed \{\} -i -e "/^\  name: .*/ a\
\  namespace: flux-master" \;

    mkdir -p output/yaml/flux
    cp output/tmp/gen/flux/templates/*.yaml output/yaml/flux
    rm -rf output/tmp
}

function generate_prometheus_yaml() {
    echo Generating Prometheus operator files from Helm charts...

    rm -rf output/tmp
    mkdir -p output/tmp/work
#    mkdir -p output/tmp/charts
#    mkdir -p output/tmp/gen

#    helm fetch --untar --untardir output/tmp/charts 'stable/prometheus-operator'
#    helm template -n prometheus-operator \
#        --namespace prometheus \
#        --output-dir output/tmp/gen \
#        output/tmp/charts/prometheus-operator
#
#    find output/tmp/prometheus/flux/templates -name *.yaml -exec sed \{\} -i -e "/^\  name: .*/ a\
#\  namespace: flux-master" \;
#
#    mkdir -p output/yaml/flux
#    cp output/tmp/prometheus/flux/templates/*.yaml output/yaml/flux
#    rm -rf output/tmp

    git clone https://github.com/coreos/prometheus-operator.git -b v0.29.0 output/tmp/work

    mkdir -p output/yaml/prometheus
    cp -r output/tmp/work/contrib/kube-prometheus/manifests/*.yaml output/yaml/prometheus
    rm -rf output/tmp
}

process_arguments $@

rm -rf output
mkdir output
generate_templated_yaml

helm init --client-only
generate_flux_yaml
generate_prometheus_yaml
