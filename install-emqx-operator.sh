#!/usr/bin/env bash

set -euo pipefail

CLUSTER_NAME=${CLUSTER_NAME:-emqx}
REGION=${REGION:-eu-north-1}

helm repo add jetstack https://charts.jetstack.io
helm repo add emqx https://repos.emqx.io/charts
helm repo add eks https://aws.github.io/eks-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set crds.enabled=true
vpc_id=$(aws ec2 describe-vpcs --region "${REGION}" --filters Name=tag:Name,Values=eksctl-${CLUSTER_NAME}-cluster/VPC --query 'Vpcs[0].VpcId' --output text)
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=emqx \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=${REGION} \
  --set vpcId=${vpc_id}
kubectl wait --for=condition=Ready pods -l "app.kubernetes.io/name=aws-load-balancer-controller" -n kube-system
helm upgrade --install emqx-operator emqx/emqx-operator --namespace emqx-operator-system --create-namespace
kubectl wait --for=condition=Ready pods -l "control-plane=controller-manager" -n emqx-operator-system
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false
kubectl wait --for=condition=Ready pods -l "app.kubernetes.io/name=prometheus" -n monitoring --timeout=300s
