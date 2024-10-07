# Deploying EMQX Enterprise to AWS EKS with EMQX Operator

## Pre-requisites

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- [eksctl](https://docs.aws.amazon.com/eks/latest/userguide/getting-started-eksctl.html)
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

## Create EKS Cluster and setup EMQX Operator

```bash
./create-eks-cluster.sh
./install-emqx-operator.sh
```

## Deploy EMQX

Add your license into `manifests/emqx-license.yaml` and apply the manifests:

```bash
kubectl apply -f manifests
```
