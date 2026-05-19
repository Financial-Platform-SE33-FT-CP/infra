#!/bin/bash
set -euo pipefail

# ============================================================
# 会计平台 — Docker Swarm 部署验证脚本
# ============================================================

STACK_NAME="accounting-platform"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "🔍 验证 Swarm Stack '${STACK_NAME}' ..."
echo ""

# --------------------------------------------------
# 1. 集群基本信息
# --------------------------------------------------
echo -e "${BLUE}▶ 集群节点${NC}"
docker node ls
echo ""

# --------------------------------------------------
# 2. Stack 服务列表
# --------------------------------------------------
echo -e "${BLUE}▶ 服务列表${NC}"
docker service ls --filter name="${STACK_NAME}"
echo ""

# --------------------------------------------------
# 3. 任务状态检查
# --------------------------------------------------
echo -e "${BLUE}▶ 任务状态${NC}"
docker stack ps "${STACK_NAME}" --format 'table {{.Name}}\t{{.CurrentState}}\t{{.Error}}'
echo ""

# --------------------------------------------------
# 4. 检查不健康的任务
# --------------------------------------------------
echo -e "${BLUE}▶ 健康检查${NC}"
UNHEALTHY=$(docker stack ps "${STACK_NAME}" --format '{{.CurrentState}}' | grep -v 'Running\|Shutdown\|Complete' || true)
if [ -n "$UNHEALTHY" ]; then
    echo -e "${YELLOW}⚠️ 发现非正常运行状态的任务:${NC}"
    docker stack ps "${STACK_NAME}" --filter "desired-state=running" | grep -v 'Running' || true
else
    echo -e "${GREEN}✅ 所有任务运行正常${NC}"
fi
echo ""

# --------------------------------------------------
# 5. 网络检查
# --------------------------------------------------
echo -e "${BLUE}▶ 网络${NC}"
docker network ls --filter name="${STACK_NAME}"
echo ""

# --------------------------------------------------
# 6. 存储卷检查
# --------------------------------------------------
echo -e "${BLUE}▶ 存储卷${NC}"
docker volume ls --filter name="${STACK_NAME}"
echo ""

# --------------------------------------------------
# 7. Secrets 检查
# --------------------------------------------------
echo -e "${BLUE}▶ Secrets${NC}"
for secret in database_url postgres_password jwt_secret grafana_admin_password; do
    if docker secret ls --format '{{.Name}}' | grep -q "^${secret}$"; then
        echo -e "  ${GREEN}✓${NC} ${secret}"
    else
        echo -e "  ${RED}✗${NC} ${secret} (缺失)"
    fi
done
echo ""

# --------------------------------------------------
# 8. 资源使用概览
# --------------------------------------------------
echo -e "${BLUE}▶ 资源使用 (各服务限制/预留)${NC}"
docker service ls --filter name="${STACK_NAME}" --format '{{.Name}}' | while read svc; do
    inspect=$(docker service inspect --format '{{json .Spec.TaskTemplate.Resources}}' "$svc" 2>/dev/null || echo '{}')
    limits_cpu=$(echo "$inspect" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("Limits",{}).get("NanoCPUs",0)/1e9)' 2>/dev/null || echo "?")
    limits_mem=$(echo "$inspect" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("Limits",{}).get("MemoryBytes",0)//1024//1024)' 2>/dev/null || echo "?")
    res_cpu=$(echo "$inspect" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("Reservations",{}).get("NanoCPUs",0)/1e9)' 2>/dev/null || echo "?")
    res_mem=$(echo "$inspect" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("Reservations",{}).get("MemoryBytes",0)//1024//1024)' 2>/dev/null || echo "?")
    replicas=$(docker service inspect --format '{{.Spec.Mode.Replicated.Replicas}}' "$svc" 2>/dev/null || echo "?")
    printf "  %-30s replicas=%s  limits=%sCPU/%sMB  reservations=%sCPU/%sMB\n" "$svc" "$replicas" "$limits_cpu" "$limits_mem" "$res_cpu" "$res_mem"
done
echo ""

echo -e "${GREEN}✅ 验证完成${NC}"
