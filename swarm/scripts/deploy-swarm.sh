#!/bin/bash
set -euo pipefail

# ============================================================
# 会计平台 — Docker Swarm Stack 部署脚本
# ============================================================

STACK_NAME="accounting-platform"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWARM_DIR="$(dirname "${SCRIPT_DIR}")"
COMPOSE_FILE="${SWARM_DIR}/docker-compose.swarm.yml"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "🚀 部署会计平台到 Docker Swarm..."
echo ""

# --------------------------------------------------
# 1. 检查 Swarm 状态
# --------------------------------------------------
if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
    echo -e "${RED}❌ 当前节点未加入 Docker Swarm。${NC}"
    echo "   请先运行: docker swarm init"
    echo "   或: docker swarm join --token <TOKEN> <MANAGER-IP>:2377"
    exit 1
fi

NODE_ROLE=$(docker info --format '{{.Swarm.ControlAvailable}}')
if [ "$NODE_ROLE" != "true" ]; then
    echo -e "${YELLOW}⚠️ 当前节点不是 Manager。请在 Manager 节点上运行此脚本。${NC}"
    exit 1
fi

# --------------------------------------------------
# 2. 检查 Secrets
# --------------------------------------------------
MISSING_SECRETS=()
for secret in database_url postgres_password jwt_secret grafana_admin_password; do
    if ! docker secret ls --format '{{.Name}}' | grep -q "^${secret}$"; then
        MISSING_SECRETS+=("$secret")
    fi
done

if [ ${#MISSING_SECRETS[@]} -gt 0 ]; then
    echo -e "${RED}❌ 以下 Docker Secrets 不存在:${NC}"
    for s in "${MISSING_SECRETS[@]}"; do
        echo "   - $s"
    done
    echo ""
    echo "请先运行: ./scripts/init-secrets.sh"
    exit 1
fi

echo -e "${GREEN}✅ Secrets 检查通过${NC}"

# --------------------------------------------------
# 3. 检查环境变量
# --------------------------------------------------
MISSING_ENV=()
if [ -z "${DATABASE_URL:-}" ]; then
    MISSING_ENV+=("DATABASE_URL")
fi
if [ -z "${JWT_SECRET:-}" ]; then
    MISSING_ENV+=("JWT_SECRET")
fi

if [ ${#MISSING_ENV[@]} -gt 0 ]; then
    echo -e "${RED}❌ 以下环境变量未设置:${NC}"
    for e in "${MISSING_ENV[@]}"; do
        echo "   - $e"
    done
    echo ""
    echo "请先执行: source env.swarm"
    exit 1
fi

echo -e "${GREEN}✅ 环境变量检查通过${NC}"

# --------------------------------------------------
# 4. 检查数据节点标签 (可选但推荐)
# --------------------------------------------------
if ! docker node ls --filter "label=storage=persistent" --format '{{.ID}}' | grep -q .; then
    echo -e "${YELLOW}⚠️ 警告: 没有节点被打上 'storage=persistent' 标签。${NC}"
    echo "   postgres / redis 将无法调度，因为它们需要此约束。"
    echo ""
    echo "   如需标记节点，请在目标节点执行:"
    echo "   docker node update --label-add storage=persistent <NODE-ID>"
    echo ""
    read -rp "   是否继续部署? [y/N]: " answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# --------------------------------------------------
# 5. 部署 Stack
# --------------------------------------------------
echo ""
echo -e "${BLUE}▶ 正在部署 Stack '${STACK_NAME}'...${NC}"
docker stack deploy -c "${COMPOSE_FILE}" "${STACK_NAME}"

echo ""
echo -e "${GREEN}✅ Stack '${STACK_NAME}' 部署完成！${NC}"
echo ""
echo "常用命令:"
echo "   查看服务列表   docker service ls --filter name=${STACK_NAME}"
echo "   查看任务状态   docker stack ps ${STACK_NAME}"
echo "   查看服务日志   docker service logs -f ${STACK_NAME}_auth-service"
echo "   扩容服务       docker service scale ${STACK_NAME}_auth-service=5"
echo "   删除 Stack     docker stack rm ${STACK_NAME}"
echo ""
