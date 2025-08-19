#!/bin/bash
#
#  Copyright (c) 2025 Metaform Systems, Inc.
#
#  This program and the accompanying materials are made available under the
#  terms of the Apache License, Version 2.0 which is available at
#  https://www.apache.org/licenses/LICENSE-2.0
#
#  SPDX-License-Identifier: Apache-2.0
#
#  Contributors:
#       Metaform Systems, Inc. - initial API and implementation
#
#

set -euxo pipefail

function load_images() {
    local cluster_name=$1
    kind load docker-image controlplane:latest identity-hub:latest catalog-server:latest dataplane:latest issuerservice:latest -n "$cluster_name"
}

# create origin cluster
echo "Preparing origin cluster"
kind create cluster -n staging --config kind.config.yaml --kubeconfig=./.kube/staging.config > /dev/null 2>&1
kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml --kubeconfig ./.kube/staging.config

load_images staging > /dev/null 2>&1
liqoctl install kind --cluster-id staging --cluster-labels=topology.liqo.io/type=origin --kubeconfig ./.kube/staging.config

# create remote clusters
remote_clusters=("consumer-ctrl" "consumer-data" "consumer-security" "mvd-issuer" "provider-ctrl" "provider-security" "provider-data-qna" "provider-data-manufacturing")

for cluster in "${remote_clusters[@]}"
do
    echo "Create remote cluster $cluster"
    kind create cluster -n "$cluster" --config remote-cluster.yaml --kubeconfig="./.kube/$cluster.config" > /dev/null 2>&1
    load_images $cluster > /dev/null 2>&1
done

# Deploy MVD
echo "Deploy MVD"
tofu apply -auto-approve

echo "Waiting for staging cluster to be ready..."
kubectl wait --namespace ingress-nginx \
            --for=condition=ready pod \
            --selector=app.kubernetes.io/component=controller \
            --timeout=90s \
            --kubeconfig ./.kube/staging.config

for cluster in "${remote_clusters[@]}"
do
    # install liqo agent
      echo "Installing LIQO agent on cluster $cluster"
      liqoctl install kind --cluster-id "$cluster" --cluster-labels=topology.liqo.io/type="$cluster" --kubeconfig "./.kube/$cluster.config"

      # peer remote cluster with origin cluster
      echo "peering cluster $cluster with staging"
      liqoctl peer --remote-kubeconfig $cluster --gw-server-service-type NodePort --kubeconfig ./.kube/staging.config

      sleep 5

      # offload pods to their respective clusters
      echo "Offload namespace $cluster to cluster $cluster"
      liqoctl offload namespace $cluster \
        --namespace-mapping-strategy EnforceSameName \
        --pod-offloading-strategy Remote \
        --selector "topology.liqo.io/type=$cluster" \
        --kubeconfig ./.kube/staging.config
done

## make all services from the ctrl cluster in the other clusters, so that those apps can access the controlplane, vault, postgres etc.
#echo "Mirror services from mvd-consumer-ctrl to -data and -security"
#liqoctl offload namespace "mvd-consumer-ctrl" \
#  --namespace-mapping-strategy EnforceSameName \
#  --pod-offloading-strategy Local \
#  --selector "topology.liqo.io/type=mvd-consumer-data" \
#  --selector "topology.liqo.io/type=mvd-consumer-security" \
#  --selector "topology.liqo.io/type=mvd-consumer-ctrl" \
#  --kubeconfig staging
#
#echo "Mirror services from mvd-provider-ctrl to -data and -security"
#liqoctl offload namespace "mvd-provider-ctrl" \
#    --namespace-mapping-strategy EnforceSameName \
#    --pod-offloading-strategy Local \
#    --selector "topology.liqo.io/type=mvd-provider-data-qna" \
#    --selector "topology.liqo.io/type=mvd-provider-data-manufacturing" \
#    --selector "topology.liqo.io/type=mvd-provider-security" \
#    --selector "topology.liqo.io/type=mvd-provider-ctrl" \
#    --kubeconfig staging

sleep 5

# restart offloaded deployments
echo "restart running deployments for LIQO to take effect"
kubectl rollout restart deployment -n mvd-consumer-ctrl --kubeconfig ./.kube/staging.config
kubectl rollout restart deployment -n mvd-consumer-data --kubeconfig ./.kube/staging.config
kubectl rollout restart deployment -n mvd-consumer-security --kubeconfig ./.kube/staging.config
kubectl rollout restart deployment -n mvd-provider-ctrl --kubeconfig ./.kube/staging.config
kubectl rollout restart deployment -n mvd-provider-data-qna --kubeconfig ./.kube/staging.config
kubectl rollout restart deployment -n mvd-provider-data-manufacturing --kubeconfig ./.kube/staging.config
kubectl rollout restart deployment -n mvd-provider-security --kubeconfig ./.kube/staging.config
kubectl rollout restart deployment -n mvd-issuer --kubeconfig ./.kube/staging.config