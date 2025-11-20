#!/usr/bin/env bash

set -euo pipefail

CLUSTER_NAME=${CLUSTER_NAME:-emqx}
REGION=${REGION:-eu-north-1}

echo "============================================"
echo "EKS Cluster Deletion Script"
echo "============================================"
echo "Cluster Name: $CLUSTER_NAME"
echo "Region: $REGION"
echo "============================================"
echo ""

# Check if cluster exists
if ! aws eks describe-cluster --name $CLUSTER_NAME --region $REGION &>/dev/null; then
    echo "Cluster '$CLUSTER_NAME' not found in region '$REGION'"
    echo "Proceeding to clean up IAM resources..."
else
    echo "✓ Cluster '$CLUSTER_NAME' found"
fi

# Function to check if resource exists before deletion
resource_exists() {
    local check_command="$1"
    eval "$check_command" &>/dev/null
}

echo ""
echo "Step 1: Deleting Load Balancers and Services..."
echo "----------------------------------------------"
# Delete any LoadBalancer services to clean up AWS NLBs/ALBs
if kubectl get svc --all-namespaces -o json 2>/dev/null | jq -e '.items[] | select(.spec.type=="LoadBalancer")' &>/dev/null; then
    echo "Found LoadBalancer services, deleting..."
    kubectl get svc --all-namespaces -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' | while read namespace name; do
        echo "  Deleting service $name in namespace $namespace..."
        kubectl delete svc -n "$namespace" "$name" --ignore-not-found=true --timeout=60s
    done
    echo "Waiting 30 seconds for AWS load balancers to be cleaned up..."
    sleep 30
else
    echo "No LoadBalancer services found"
fi

echo ""
echo "Step 2: Deleting EBS CSI Driver Addon..."
echo "----------------------------------------------"
if resource_exists "aws eks describe-addon --cluster-name $CLUSTER_NAME --addon-name aws-ebs-csi-driver --region $REGION"; then
    echo "Deleting EBS CSI driver addon..."
    eksctl delete addon \
        --region $REGION \
        --cluster $CLUSTER_NAME \
        --name aws-ebs-csi-driver || true
    echo "✓ EBS CSI driver addon deleted"
else
    echo "EBS CSI driver addon not found"
fi

echo ""
echo "Step 3: Deleting IAM Service Accounts..."
echo "----------------------------------------------"

# Delete AWS Load Balancer Controller Service Account
if resource_exists "aws iam get-role --role-name AmazonEKSLoadBalancerControllerRole --region $REGION"; then
    echo "Deleting AWS Load Balancer Controller IAM service account..."
    eksctl delete iamserviceaccount \
        --region $REGION \
        --cluster $CLUSTER_NAME \
        --namespace kube-system \
        --name aws-load-balancer-controller || true
    echo "✓ AWS Load Balancer Controller IAM service account deleted"
else
    echo "AWS Load Balancer Controller IAM service account not found"
fi

# Delete EBS CSI Controller Service Account
if resource_exists "aws iam get-role --role-name AmazonEKS_EBS_CSI_DriverRole --region $REGION"; then
    echo "Deleting EBS CSI Controller IAM service account..."
    eksctl delete iamserviceaccount \
        --region $REGION \
        --cluster $CLUSTER_NAME \
        --namespace kube-system \
        --name ebs-csi-controller-sa || true
    echo "✓ EBS CSI Controller IAM service account deleted"
else
    echo "EBS CSI Controller IAM service account not found"
fi

echo ""
echo "Step 4: Deleting EKS Cluster..."
echo "----------------------------------------------"
if aws eks describe-cluster --name $CLUSTER_NAME --region $REGION &>/dev/null; then
    echo "Deleting EKS cluster '$CLUSTER_NAME'..."
    echo "This will also delete:"
    echo "  - Node groups (ng1-1a, ng2-1b)"
    echo "  - Associated VPC and networking resources"
    echo "  - IAM OIDC provider"
    echo ""
    eksctl delete cluster \
        --region $REGION \
        --name $CLUSTER_NAME \
        --disable-nodegroup-eviction \
        --wait
    echo "✓ EKS cluster deleted"
else
    echo "Cluster already deleted or not found"
fi

echo ""
echo "Step 5: Cleaning up CloudFormation Stacks..."
echo "----------------------------------------------"
# Find and delete any remaining CloudFormation stacks for this cluster
STACKS=$(aws cloudformation list-stacks \
    --region $REGION \
    --stack-status-filter CREATE_COMPLETE CREATE_FAILED CREATE_IN_PROGRESS ROLLBACK_COMPLETE ROLLBACK_FAILED ROLLBACK_IN_PROGRESS UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE UPDATE_ROLLBACK_FAILED \
    --query "StackSummaries[?starts_with(StackName, 'eksctl-${CLUSTER_NAME}-')].StackName" \
    --output text 2>/dev/null || echo "")

if [ -n "$STACKS" ]; then
    echo "Found orphaned CloudFormation stacks:"
    for stack in $STACKS; do
        echo "  - $stack"
    done
    echo ""
    for stack in $STACKS; do
        echo "Deleting CloudFormation stack: $stack"
        aws cloudformation delete-stack --region $REGION --stack-name "$stack" || true
    done
    echo "Waiting for CloudFormation stacks to be deleted..."
    for stack in $STACKS; do
        echo "  Waiting for $stack..."
        aws cloudformation wait stack-delete-complete --region $REGION --stack-name "$stack" 2>/dev/null || echo "  Stack $stack deletion completed or timed out"
    done
    echo "✓ CloudFormation stacks cleaned up"
else
    echo "No orphaned CloudFormation stacks found"
fi

echo ""
echo "Step 6: Deleting IAM Policies..."
echo "----------------------------------------------"

# Delete AWS Load Balancer Controller IAM Policy
LB_POLICY_ARN=$(aws iam list-policies --region $REGION --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].Arn" --output text 2>/dev/null || echo "")
if [ -n "$LB_POLICY_ARN" ]; then
    echo "Deleting AWS Load Balancer Controller IAM policy..."
    # First, detach any policy versions if needed
    aws iam delete-policy --policy-arn "$LB_POLICY_ARN" --region $REGION || true
    echo "✓ AWS Load Balancer Controller IAM policy deleted"
else
    echo "AWS Load Balancer Controller IAM policy not found"
fi

echo ""
echo "============================================"
echo "✓ Cleanup Complete!"
echo "============================================"
echo ""
echo "All resources for cluster '$CLUSTER_NAME' have been deleted."
echo ""
echo "Note: You may want to manually verify in AWS Console:"
echo "  - EC2 > Load Balancers (any orphaned NLBs/ALBs)"
echo "  - VPC > Your VPCs (if any VPCs weren't cleaned up)"
echo "  - EC2 > Volumes (any orphaned EBS volumes)"
echo "  - IAM > Roles (any orphaned roles)"
echo ""
