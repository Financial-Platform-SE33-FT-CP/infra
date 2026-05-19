# ============================================================
# 会计平台 — 运维命令 (Docker Swarm 版本)
# ============================================================

.PHONY: help docker-up docker-down docker-dev docker-obs docker-backup \
        swarm-init swarm-deploy swarm-deploy-obs swarm-rm swarm-ps swarm-logs \
        swarm-services swarm-scale swarm-rollback validate lint

help: ## 显示帮助信息
	@echo "会计平台基础设施命令:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# --------------------------------------------------
# Docker Compose (本地开发)
# --------------------------------------------------
docker-up: ## 启动所有 Docker 服务（生产模式）
	cd docker && docker compose -f docker-compose.yml up -d

docker-down: ## 停止所有 Docker 服务
	cd docker && docker compose -f docker-compose.yml down

docker-dev: ## 启动开发模式（热重载）
	cd docker && docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d

docker-obs: ## 启动可观测性栈（本地）
	cd docker && docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d

docker-backup: ## 执行数据库备份（本地）
	cd docker && docker compose -f docker-compose.yml -f docker-compose.backup.yml --profile backup up

# --------------------------------------------------
# Docker Swarm (集群部署)
# --------------------------------------------------
swarm-init: ## 初始化 Swarm 集群提示
	@echo "在 Manager 节点运行:"
	@echo "  docker swarm init --advertise-addr <MANAGER-IP>"
	@echo ""
	@echo "Worker 节点加入:"
	@echo "  docker swarm join --token <TOKEN> <MANAGER-IP>:2377"
	@echo ""
	@echo "标记数据节点（运行 postgres/redis）:"
	@echo "  docker node update --label-add storage=persistent <NODE-ID>"

swarm-secrets: ## 创建/更新 Docker Secrets
	cd swarm && ./scripts/init-secrets.sh

swarm-deploy: ## 部署 Stack 到 Swarm
	@echo "确保已执行: source swarm/env.swarm"
	cd swarm && source env.swarm 2>/dev/null || true && ./scripts/deploy-swarm.sh

swarm-deploy-obs: ## 部署可观测性栈
	@export GRAFANA_ADMIN_USER=$${GRAFANA_ADMIN_USER:-admin} && \
	 docker stack deploy \
	   -c swarm/docker-compose.swarm.yml \
	   -c swarm/docker-compose.swarm.observability.yml \
	   accounting-platform

swarm-rm: ## 删除 Swarm Stack
	docker stack rm accounting-platform

swarm-ps: ## 查看 Swarm 任务状态
	docker stack ps accounting-platform

swarm-services: ## 查看 Swarm 服务列表
	docker service ls --filter name=accounting-platform

swarm-logs: ## 查看所有服务日志 (svc=auth-service)
	@if [ -z "$(svc)" ]; then \
	  echo "用法: make swarm-logs svc=auth-service"; \
	  exit 1; \
	fi
	docker service logs -f --tail 100 accounting-platform_$(svc)

swarm-scale: ## 手动扩缩容 (svc=auth-service replicas=5)
	@if [ -z "$(svc)" ] || [ -z "$(replicas)" ]; then \
	  echo "用法: make swarm-scale svc=auth-service replicas=5"; \
	  exit 1; \
	fi
	docker service scale accounting-platform_$(svc)=$(replicas)

swarm-rollback: ## 回滚指定服务 (svc=auth-service)
	@if [ -z "$(svc)" ]; then \
	  echo "用法: make swarm-rollback svc=auth-service"; \
	  exit 1; \
	fi
	docker service update --rollback accounting-platform_$(svc)

# --------------------------------------------------
# 备份
# --------------------------------------------------
swarm-backup: ## 手动执行数据库备份
	cd swarm && ./scripts/run-backup.sh

# --------------------------------------------------
# 验证
# --------------------------------------------------
validate: ## 验证所有配置文件
	@echo "=== Swarm Compose ==="
	@export DATABASE_URL="postgresql+asyncpg://accounting:pass@postgres:5432/accounting" && \
	 export JWT_SECRET="test-secret" && \
	 cd swarm && docker compose -f docker-compose.swarm.yml config > /dev/null
	@echo "=== Swarm Observability ==="
	@export GRAFANA_ADMIN_PASSWORD="test" && \
	 cd swarm && docker compose -f docker-compose.swarm.observability.yml config > /dev/null
	@echo "=== Local Dev Compose ==="
	@cd docker && docker compose -f docker-compose.yml -f docker-compose.dev.yml config > /dev/null
	@echo "=== 全部通过 ==="

lint: ## 代码检查（pre-commit）
	pre-commit run --all-files
