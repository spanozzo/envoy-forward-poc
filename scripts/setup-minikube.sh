#!/usr/bin/env bash
set -euo pipefail

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