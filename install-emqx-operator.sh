#!/usr/bin/env bash

set -euo pipefail

helm repo add jetstack https://charts.jetstack.io
helm repo add emqx https://repos.emqx.io/charts
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set installCRDs=true
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=emqx \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
helm upgrade --install emqx-operator emqx/emqx-operator --namespace emqx-operator-system --create-namespace
kubectl wait --for=condition=Ready pods -l "control-plane=controller-manager" -n emqx-operator-system
