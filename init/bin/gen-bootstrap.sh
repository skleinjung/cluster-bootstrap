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

function generate_helm_yaml() {
    echo Generating yaml files from Helm charts...

    rm -rf output/tmp
    mkdir -p output/tmp/helm
    mkdir -p output/tmp/output
    git clone https://github.com/weaveworks/flux.git output/tmp/flux -b ${FLUX_VERSION}

    helm template -n flux-master \
        --namespace kube-system \
        --output-dir output/tmp/helm \
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
        output/tmp/flux/chart/flux

    find output/tmp/helm/flux/templates -name *.yaml -exec sed \{\} -i -e "/^\  name: .*/ a\
\  namespace: flux-master" \;

    cp output/tmp/helm/flux/templates/*.yaml output/yaml
    rm -rf output/tmp
}

process_arguments $@

rm -rf output
mkdir output
generate_templated_yaml
generate_helm_yaml
