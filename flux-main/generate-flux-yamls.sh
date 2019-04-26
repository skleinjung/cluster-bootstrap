#!/bin/bash

# helm must be installed first
mkdir -p flux-gen

git clone https://github.com/weaveworks/flux.git flux-chart
helm template --output-dir flux-gen --name flux --namespace flux \
    --set git.url=git@github.com:skleinjung/thrashplay-deployment \
    --set git.path=deployments \
    --set git.pollInterval=1m \
    --set registry.pollInterval=1m \
    --set helmOperator.create=true \
    --set helmOperator.createCRD=false \
    --set helmOperator.git.pollInterval=3m \
    --set helmOperator.tls.enable=true \
    --set helmOperator.tls.verify=true \
    --set helmOperator.tls.caContent="$(cat ./tls/ca.cert.pem)" \
    --set prometheus.enabled=true \
    flux-chart/chart/flux

rm -rf flux-chart
