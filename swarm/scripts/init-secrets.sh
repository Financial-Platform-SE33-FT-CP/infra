#!/bin/bash
set -euo pipefail

# ============================================================
# 会计平台 — Docker Swarm Secrets 初始化脚本
# ============================================================
# 用法:
#   ./scripts/init-secrets.sh
#
# 注意: Docker Secret 一旦创建不可修改，只能删除重建。
#       删除 secret 前需先删除所有引用该 secret 的服务。
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ensure_swarm() {
    if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
        echo -e "${RED}❌ 当前节点未加入 Docker Swarm。${NC}"
        echo "   请先运行: docker swarm init"
        exit 1
    fi
}

prompt_secret() {
    local name=$1
    local description=$2
    local current_value=""

    # 检查是否已存在
    if docker secret ls --format '{{.Name}}' | grep -q "^${name}$"; then
        echo -e "${YELLOW}⚠️ Secret '${name}' 已存在。${NC}"
        read -rp "   是否删除并重新创建? [y/N]: " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}   正在删除旧 secret '${name}'...${NC}"
            docker secret rm "${name}" || true
        else
            echo "   跳过 '${name}'"
            return
        fi
    fi

    echo ""
    echo "▸ ${description}"
    read -rsp "   请输入 ${name} (输入不可见): " value
    echo ""

    if [ -z "$value" ]; then
        echo -e "${RED}   错误: ${name} 不能为空${NC}"
        exit 1
    fi

    echo -n "$value" | docker secret create "${name}" -
    echo -e "${GREEN}   ✅ Secret '${name}' 创建成功${NC}"
}

main() {
    echo "🔐 初始化 Docker Swarm Secrets..."
    ensure_swarm
    echo ""

    prompt_secret "database_url" \
        "数据库连接字符串 (DATABASE_URL)\n     示例: postgresql+asyncpg://accounting:password@postgres:5432/accounting"

    prompt_secret "postgres_password" \
        "PostgreSQL 密码 (POSTGRES_PASSWORD)\n     示例: your-secure-postgres-password"

    prompt_secret "jwt_secret" \
        "JWT 签名密钥 (JWT_SECRET)\n     建议至少 32 位随机字符串"

    prompt_secret "grafana_admin_password" \
        "Grafana 管理员密码 (GRAFANA_ADMIN_PASSWORD)\n     用于登录 Grafana 监控面板"

    echo ""
    echo -e "${GREEN}🎉 所有 Secrets 初始化完成！${NC}"
    echo ""
    echo "当前 secrets 列表:"
    docker secret ls --filter label!=com.docker.stack.namespace
    echo ""
    echo "下一步:"
    echo "   1. source env.swarm"
    echo "   2. ./scripts/deploy-swarm.sh"
}

main "$@"
