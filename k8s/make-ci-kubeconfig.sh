#!/usr/bin/env bash
# Print a kubeconfig for the ci-deployer service account (k8s/ci-deployer.yaml).
#   KUBECONFIG=.generated/kubeconfig ./k8s/make-ci-kubeconfig.sh https://203.0.113.10:6443 > ci-kubeconfig
set -euo pipefail
server=${1:?usage: $0 <api-server-url>}

token=$(kubectl -n kube-system get secret ci-deployer-token -o jsonpath='{.data.token}' | base64 -d)
ca=$(kubectl -n kube-system get secret ci-deployer-token -o jsonpath='{.data.ca\.crt}')

cat <<YAML
apiVersion: v1
kind: Config
clusters:
  - name: platform
    cluster: {server: "$server", certificate-authority-data: "$ca"}
users:
  - name: ci-deployer
    user: {token: "$token"}
contexts:
  - name: ci
    context: {cluster: platform, user: ci-deployer}
current-context: ci
YAML
