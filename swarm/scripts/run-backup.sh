#!/bin/bash
set -euo pipefail

# ============================================================
# 会计平台 — PostgreSQL 手动/定时备份脚本
# ============================================================
# 用法:
#   ./scripts/run-backup.sh
#
# 定时备份: 在 Swarm Manager 节点的 crontab 中添加:
#   0 2 * * * /opt/accounting/scripts/run-backup.sh >> /var/log/accounting-backup.log 2>&1
# ============================================================

STACK_NAME="accounting-platform"
BACKUP_DIR="${BACKUP_DIR:-/opt/accounting/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

mkdir -p "${BACKUP_DIR}"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/accounting_${TIMESTAMP}.sql.gz"

echo "$(date '+%Y-%m-%d %H:%M:%S') 开始备份..."

# 通过临时容器挂载 docker secret 执行备份
# 宿主机无需知道密码，密码由 swarm secret 安全注入
docker run --rm \
    --network "${STACK_NAME}_accounting-network" \
    --secret postgres_password \
    -v "${BACKUP_DIR}:/backups" \
    -e PGHOST=postgres \
    -e PGUSER=accounting \
    -e PGDATABASE=accounting \
    -e PGPASSWORD_FILE=/run/secrets/postgres_password \
    postgres:17-alpine \
    sh -c '
        export PGPASSWORD=$(cat "$PGPASSWORD_FILE")
        pg_dump -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" | gzip > "$0"
        echo "备份完成: $0"
        find /backups -name "accounting_*.sql.gz" -mtime +$1 -delete
        echo "已清理 $1 天前的旧备份"
    ' "/backups/accounting_${TIMESTAMP}.sql.gz" "${RETENTION_DAYS}"

if [ -f "${BACKUP_FILE}" ]; then
    SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
    echo -e "${GREEN}✅ 备份成功: ${BACKUP_FILE} (${SIZE})${NC}"
else
    echo -e "${RED}❌ 备份失败${NC}"
    exit 1
fi
