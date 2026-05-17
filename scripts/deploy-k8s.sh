#!/bin/bash
set -euo pipefail

# ============================================================
# 会计平台 — Kubernetes 部署脚本
# ============================================================

NAMESPACE="accounting-platform"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../k8s"

echo "🚀 部署会计平台到 Kubernetes..."

kubectl apply -f "${K8S_DIR}/01-namespace.yml"
kubectl apply -f "${K8S_DIR}/02-configmap.yml"
kubectl apply -f "${K8S_DIR}/03-secret.yml"

for f in 10-postgres 11-redis; do
    kubectl apply -f "${K8S_DIR}/${f}.yml"
done

for f in 20-auth-service 20-tenant-service 20-coa-service 20-ledger-service 20-audit-service 20-ar-ap-service; do
    kubectl apply -f "${K8S_DIR}/${f}.yml"
done

kubectl apply -f "${K8S_DIR}/30-frontend.yml"
kubectl apply -f "${K8S_DIR}/31-nginx.yml"
kubectl apply -f "${K8S_DIR}/40-ingress.yml"

for f in 50-network-policy 51-pod-disruption-budget 52-resource-quota 53-limit-range 54-rbac; do
    kubectl apply -f "${K8S_DIR}/${f}.yml"
done

kubectl apply -f "${SCRIPT_DIR}/../backup/pg-backup.yml"

echo "✅ 部署完成！"
