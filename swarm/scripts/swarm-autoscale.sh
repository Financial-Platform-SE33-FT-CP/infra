#!/bin/bash

# ============================================================
# 会计平台 — 简易 Swarm 自动扩缩容示例脚本
# ============================================================
# 说明:
#   Docker Swarm 不原生支持 HPA。此脚本演示如何基于
#   服务任务平均 CPU 使用率进行手动/自动扩缩容。
#
# 用法:
#   # 手动检查并扩容 auth-service
#   ./scripts/swarm-autoscale.sh auth-service 70 10
#
#   # 配合 cron 定时执行 (每 5 分钟)
#   */5 * * * * /opt/accounting/infra/swarm/scripts/swarm-autoscale.sh auth-service 70 10
#
# 参数:
#   $1 = 服务名 (不含 stack 前缀, 如 auth-service)
#   $2 = CPU 阈值百分比 (默认 70)
#   $3 = 最大副本数 (默认 10)
# ============================================================

STACK_NAME="accounting-platform"
SERVICE="${STACK_NAME}_${1:-}"
THRESHOLD="${2:-70}"
MAX_REPLICAS="${3:-10}"
MIN_REPLICAS=2

if [ -z "${1:-}" ]; then
    echo "用法: $0 <service-name> [cpu-threshold] [max-replicas]"
    echo "示例: $0 auth-service 70 10"
    exit 1
fi

# 获取当前副本数
CURRENT=$(docker service inspect --format '{{.Spec.Mode.Replicated.Replicas}}' "$SERVICE" 2>/dev/null || echo "0")
if [ "$CURRENT" = "0" ]; then
    echo "❌ 服务 $SERVICE 不存在或副本数为 0"
    exit 1
fi

# 获取平均 CPU 使用率 (基于最近 1 分钟的 docker stats)
# 注意: 这需要容器支持 metrics，且精度有限，仅供参考
CPU_PCT=0
TASKS=$(docker service ps "$SERVICE" --filter "desired-state=running" --format '{{.ID}}')
TASK_COUNT=0
for task_id in $TASKS; do
    container_id=$(docker inspect --format '{{.Status.ContainerStatus.ContainerID}}' "$task_id" 2>/dev/null || true)
    if [ -n "$container_id" ]; then
        stats=$(docker stats --no-stream --format '{{.CPUPerc}}' "$container_id" 2>/dev/null || echo "0%")
        pct=$(echo "$stats" | sed 's/%//')
        if [ -n "$pct" ]; then
            CPU_PCT=$(awk "BEGIN {print $CPU_PCT + $pct}")
            TASK_COUNT=$((TASK_COUNT + 1))
        fi
    fi
done

if [ "$TASK_COUNT" -gt 0 ]; then
    AVG_CPU=$(awk "BEGIN {printf \"%.1f\", $CPU_PCT / $TASK_COUNT}")
else
    AVG_CPU=0
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') $SERVICE current=$CURRENT avg_cpu=${AVG_CPU}% threshold=${THRESHOLD}% max=$MAX_REPLICAS"

# 扩容判断
if (( $(echo "$AVG_CPU > $THRESHOLD" | bc -l) )) && [ "$CURRENT" -lt "$MAX_REPLICAS" ]; then
    NEW=$((CURRENT + 1))
    echo "  ⬆️ 扩容: $CURRENT -> $NEW"
    docker service scale "${SERVICE}=${NEW}"
# 缩容判断 (低于阈值 50% 且高于最小副本)
elif (( $(echo "$AVG_CPU < $(echo "$THRESHOLD * 0.5" | bc -l)" | bc -l) )) && [ "$CURRENT" -gt "$MIN_REPLICAS" ]; then
    NEW=$((CURRENT - 1))
    echo "  ⬇️ 缩容: $CURRENT -> $NEW"
    docker service scale "${SERVICE}=${NEW}"
else
    echo "  ➡️ 保持不变"
fi
