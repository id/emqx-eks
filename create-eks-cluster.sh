#!/usr/bin/env bash

set -euo pipefail

CLUSTER_NAME=${CLUSTER_NAME:-emqx}
REGION=${REGION:-eu-north-1}

cat <<EOF | eksctl create cluster -f -
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: ${REGION}
  version: "1.34"

nodeGroups:
  - name: ng1-1a
    amiFamily: AmazonLinux2023
    instanceType: m7i.xlarge
    availabilityZones:
      - ${REGION}a
    minSize: 1
    maxSize: 1
  - name: ng2-1b
    amiFamily: AmazonLinux2023
    instanceType: m7i.xlarge
    availabilityZones:
      - ${REGION}b
    minSize: 1
    maxSize: 1
EOF

eksctl utils associate-iam-oidc-provider --region $REGION --cluster $CLUSTER_NAME --approve
eksctl create iamserviceaccount \
    --region $REGION \
    --name ebs-csi-controller-sa \
    --namespace kube-system \
    --cluster $CLUSTER_NAME \
    --role-name AmazonEKS_EBS_CSI_DriverRole \
    --role-only \
    --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
    --approve

SA_ROLE_ARN=$(aws iam list-roles --region $REGION --query "Roles[?RoleName=='AmazonEKS_EBS_CSI_DriverRole'].Arn" --output text)
eksctl create addon \
    --region $REGION \
    --cluster $CLUSTER_NAME \
    --name aws-ebs-csi-driver \
    --service-account-role-arn "$SA_ROLE_ARN" \
    --force

wget -nc -q https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.4/docs/install/iam_policy.json
aws iam create-policy \
    --region $REGION \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json
LB_POLICY_ARN=$(aws iam list-policies --region $REGION --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].Arn" --output text)
eksctl create iamserviceaccount \
    --region $REGION \
    --cluster $CLUSTER_NAME \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --role-name AmazonEKSLoadBalancerControllerRole \
    --attach-policy-arn="$LB_POLICY_ARN" \
    --approve

aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
