#!/usr/bin/env bash
# ============================================================
# 会计平台 — 单机 Compose 远程部署脚本
# 目标主机: root@sfxfs.org
# ============================================================
set -euo pipefail

# --------------------------------------------------
# 配置
# --------------------------------------------------
REMOTE_HOST="root@sfxfs.org"
REMOTE_APP_DIR="/opt/accounting-platform"
GHCR_USERNAME="financial-platform-se33-ft-cp"
# 从环境变量或文件读取，避免硬编码在仓库中
GHCR_TOKEN="${GHCR_TOKEN:-}"
if [ -z "$GHCR_TOKEN" ] && [ -f "${SCRIPT_DIR}/.ghcr_token" ]; then
  GHCR_TOKEN="$(cat "${SCRIPT_DIR}/.ghcr_token")"
fi
if [ -z "$GHCR_TOKEN" ]; then
  error "请设置 GHCR_TOKEN 环境变量或创建 .ghcr_token 文件"
fi

# 本地文件路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_DIR="${SCRIPT_DIR}/infra/docker"
NGINX_CONF="${DOCKER_DIR}/nginx/default.conf"
COMPOSE_FILE="${DOCKER_DIR}/docker-compose.prod.yml"
ENV_FILE="${DOCKER_DIR}/.env"

# --------------------------------------------------
# 颜色输出
# --------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# --------------------------------------------------
# 1. 检查本地文件
# --------------------------------------------------
info "检查本地文件..."
for f in "$NGINX_CONF" "$COMPOSE_FILE"; do
  if [ ! -f "$f" ]; then
    error "缺少文件: $f"
  fi
done

if [ ! -f "$ENV_FILE" ]; then
  warn ".env 不存在，将使用 env.production.example"
  ENV_FILE="${DOCKER_DIR}/env.production.example"
fi

# --------------------------------------------------
# 2. 连接检查
# --------------------------------------------------
info "连接目标主机 ${REMOTE_HOST}..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "${REMOTE_HOST}" "echo ok" &>/dev/null; then
  info "尝试使用密码登录..."
  if ! ssh -o ConnectTimeout=5 "${REMOTE_HOST}" "echo ok" &>/dev/null; then
    error "无法连接到 ${REMOTE_HOST}，请检查网络和 SSH 配置"
  fi
fi

# --------------------------------------------------
# 3. 远程准备环境
# --------------------------------------------------
info "检查远程 Docker 环境..."
ssh "${REMOTE_HOST}" bash -s << 'REMOTE_BOOTSTRAP'
set -e

# Install Docker if not present
if ! command -v docker &>/dev/null; then
  echo "[INFO] 安装 Docker..."
  curl -fsSL https://get.docker.com | sh
fi

# Install docker compose plugin if missing
if ! docker compose version &>/dev/null; then
  echo "[INFO] 安装 docker compose plugin..."
  apt-get update -qq && apt-get install -y -qq docker-compose-plugin 2>/dev/null || true
fi

# Start Docker daemon if not running
if ! docker info &>/dev/null; then
  echo "[INFO] 启动 Docker..."
  systemctl start docker || service docker start
fi

echo "[INFO] Docker 环境就绪"
REMOTE_BOOTSTRAP

# --------------------------------------------------
# 4. 上传文件
# --------------------------------------------------
info "上传部署文件到 ${REMOTE_APP_DIR}..."
ssh "${REMOTE_HOST}" "mkdir -p ${REMOTE_APP_DIR}/nginx"

scp "$COMPOSE_FILE" "${REMOTE_HOST}:${REMOTE_APP_DIR}/docker-compose.yml"
scp "$NGINX_CONF"   "${REMOTE_HOST}:${REMOTE_APP_DIR}/nginx/default.conf"
scp "$ENV_FILE"     "${REMOTE_HOST}:${REMOTE_APP_DIR}/.env"

# --------------------------------------------------
# 5. 登录 GHCR 并部署
# --------------------------------------------------
info "登录 GHCR 并部署服务..."
ssh "${REMOTE_HOST}" bash -s << DEPLOY
set -e

cd ${REMOTE_APP_DIR}

# 登录 GHCR
echo "${GHCR_TOKEN}" | docker login ghcr.io -u ${GHCR_USERNAME} --password-stdin

# 拉取最新镜像
echo "[INFO] 拉取镜像..."
docker compose pull

# 启动/更新服务
echo "[INFO] 启动服务..."
docker compose --env-file .env up -d --remove-orphans

# 等待健康检查
echo "[INFO] 等待服务就绪 (最多 120 秒)..."
WAIT=0
while [ \$WAIT -lt 120 ]; do
  UNHEALTHY=\$(docker compose ps --format json 2>/dev/null | grep -v '"Health":"healthy"' | grep -c '"Health":' || true)
  if [ "\$UNHEALTHY" = "0" ]; then
    echo "[INFO] 所有服务健康!"
    break
  fi
  sleep 5
  WAIT=\$((WAIT + 5))
  echo "  ...等待中 (已等 \${WAIT}s)"
done

echo ""
echo "=== 服务状态 ==="
docker compose ps
DEPLOY

# --------------------------------------------------
# 6. 完成
# --------------------------------------------------
echo ""
info "=============================="
info " 部署完成!"
info " 访问 http://sfxfs.org"
info "=============================="
info ""
info "管理命令 (SSH 到主机后):"
info "  cd ${REMOTE_APP_DIR}"
info "  docker compose ps              # 查看状态"
info "  docker compose logs -f         # 查看日志"
info "  docker compose down            # 停止服务"
info "  docker compose up -d           # 重新启动"
info "  docker compose pull && docker compose up -d  # 更新并重启"
