#!/usr/bin/env bash
set -euo pipefail

CNPG_VERSION="1.28.1"
CNPG_RELEASE_BRANCH="release-1.28"
CERT_MANAGER_VERSION="1.19.2"
BARMAN_VERSION="0.11.0"
EG_VERSION="v1.7.0"
CILIUM_VERSION="1.19.0"
NAMESPACE="envoy-poc"
MINIKUBE_MEMORY="4096"
MINIKUBE_CPUS="4"

echo "==> Starting minikube..."
if minikube status &>/dev/null; then
  echo "    minikube already running, skipping start"
else
  minikube start \
    --network-plugin=cni \
    --cni=false \
    --memory="${MINIKUBE_MEMORY}" \
    --cpus="${MINIKUBE_CPUS}"
fi

echo "==> Installing Cilium with Hubble..."
if helm status cilium -n kube-system &>/dev/null; then
  echo "    Cilium already installed, skipping"
else
  helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
  helm repo update cilium
  helm upgrade cilium cilium/cilium \
    --version "${CILIUM_VERSION}" \
    -n kube-system \
    --set operator.replicas=1 \
    --set hubble.enabled=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true
fi

echo "==> Waiting for Cilium to be ready..."
kubectl -n kube-system rollout status daemonset/cilium --timeout=120s
kubectl -n kube-system rollout status deployment/hubble-relay --timeout=120s

echo "==> Installing Envoy Gateway ${EG_VERSION}..."
if helm status eg -n envoy-gateway-system &>/dev/null; then
  echo "    Envoy Gateway already installed, skipping"
else
  helm install eg oci://docker.io/envoyproxy/gateway-helm \
    --version "${EG_VERSION}" \
    -n envoy-gateway-system \
    --create-namespace \
    --set config.envoyGateway.extensionApis.enableBackend=true
fi

echo "==> Waiting for Envoy Gateway to be ready..."
kubectl -n envoy-gateway-system rollout status deployment/envoy-gateway --timeout=120s

echo "==> Installing cert-manager v${CERT_MANAGER_VERSION}..."
if kubectl get namespace cert-manager &>/dev/null; then
  echo "    cert-manager already installed, skipping"
else
  kubectl apply --server-side -f \
    "https://github.com/cert-manager/cert-manager/releases/download/v${CERT_MANAGER_VERSION}/cert-manager.yaml"
fi

echo "==> Waiting for cert-manager operator to be ready..."
kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=120s

echo "==> Installing CNPG operator v${CNPG_VERSION}..."
if kubectl get namespace cnpg-system &>/dev/null; then
  echo "    CNPG operator already installed, skipping"
else
  kubectl apply --server-side -f \
    "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/${CNPG_RELEASE_BRANCH}/releases/cnpg-${CNPG_VERSION}.yaml"
fi

echo "==> Waiting for CNPG operator to be ready..."
kubectl -n cnpg-system rollout status deployment/cnpg-controller-manager --timeout=120s

echo "==> Installing Barman plugin v${BARMAN_VERSION}..."
if kubectl get deployment barman-cloud -n cnpg-system &>/dev/null; then
  echo "    Barman plugin already installed, skipping"
else
  kubectl apply --server-side -f \
    "https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v${BARMAN_VERSION}/manifest.yaml"
fi

echo "==> Waiting for Barman plugin to be ready..."
kubectl -n cnpg-system rollout status deployment/barman-cloud --timeout=120s

echo "==> Creating namespace ${NAMESPACE}..."
if kubectl get namespace "${NAMESPACE}" &>/dev/null; then
  echo "    Namespace ${NAMESPACE} already exists, skipping"
else
  kubectl create namespace "${NAMESPACE}"
fi