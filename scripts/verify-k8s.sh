#!/bin/bash
set -euo pipefail

NAMESPACE="accounting-platform"

echo "🔍 验证部署状态..."
kubectl get pods -n ${NAMESPACE}
kubectl get svc -n ${NAMESPACE}
kubectl get hpa -n ${NAMESPACE} 2>/dev/null || true
