#!/bin/bash
set -euo pipefail

# ============================================================
# 会计平台 — Helm 部署脚本
# ============================================================

NAMESPACE="accounting-platform"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Helm 部署会计平台..."

helm upgrade --install accounting-platform "${SCRIPT_DIR}/../helm/accounting-platform" \
    --namespace ${NAMESPACE} \
    --create-namespace \
    --values "${SCRIPT_DIR}/../helm/accounting-platform/values.yaml" \
    --wait \
    --timeout 10m

echo "✅ Helm 部署完成！"
