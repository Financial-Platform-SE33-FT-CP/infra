# ============================================================
# 会计平台 — 运维命令
# ============================================================

.PHONY: help docker-up docker-down docker-obs docker-backup k8s-deploy k8s-delete \
        helm-install helm-upgrade helm-delete helm-lint tf-init tf-plan tf-apply \
        validate lint

help: ## 显示帮助信息
	@echo "会计平台基础设施命令:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# --------------------------------------------------
# Docker Compose
# --------------------------------------------------
docker-up: ## 启动所有 Docker 服务（生产模式）
	cd docker && docker compose -f docker-compose.yml up -d

docker-down: ## 停止所有 Docker 服务
	cd docker && docker compose -f docker-compose.yml down

docker-dev: ## 启动开发模式（热重载）
	cd docker && docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d

docker-obs: ## 启动可观测性栈
	cd docker && docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d

docker-backup: ## 执行数据库备份
	cd docker && docker compose -f docker-compose.yml -f docker-compose.backup.yml --profile backup up

# --------------------------------------------------
# Kubernetes (原生 manifests)
# --------------------------------------------------
k8s-deploy: ## 部署到 Kubernetes
	kubectl apply -f k8s/01-namespace.yml
	kubectl apply -f k8s/02-configmap.yml
	kubectl apply -f k8s/03-secret.yml
	kubectl apply -f k8s/10-postgres.yml -f k8s/11-redis.yml
	kubectl apply -f k8s/20-auth-service.yml -f k8s/20-tenant-service.yml \
		-f k8s/20-coa-service.yml -f k8s/20-ledger-service.yml \
		-f k8s/20-audit-service.yml -f k8s/20-ar-ap-service.yml
	kubectl apply -f k8s/30-frontend.yml -f k8s/31-nginx.yml
	kubectl apply -f k8s/40-ingress.yml
	kubectl apply -f k8s/50-network-policy.yml -f k8s/51-pod-disruption-budget.yml \
		-f k8s/52-resource-quota.yml -f k8s/53-limit-range.yml \
		-f k8s/54-rbac.yml
	kubectl apply -f backup/pg-backup.yml

k8s-delete: ## 从 Kubernetes 删除
	kubectl delete -f k8s/ --ignore-not-found=true

# --------------------------------------------------
# Helm
# --------------------------------------------------
helm-lint: ## Helm Chart 语法检查
	helm lint helm/accounting-platform

helm-template: ## 渲染 Helm 模板（不部署）
	helm template accounting-platform helm/accounting-platform \
		--namespace accounting-platform --create-namespace

helm-install: ## Helm 安装
	helm upgrade --install accounting-platform helm/accounting-platform \
		--namespace accounting-platform --create-namespace \
		--values helm/accounting-platform/values.yaml

helm-upgrade: ## Helm 升级
	helm upgrade accounting-platform helm/accounting-platform \
		--namespace accounting-platform

helm-delete: ## Helm 卸载
	helm uninstall accounting-platform --namespace accounting-platform

# --------------------------------------------------
# Terraform
# --------------------------------------------------
tf-init: ## Terraform 初始化
	cd terraform && terraform init

tf-plan: ## Terraform 计划
	cd terraform && terraform plan -var-file=terraform.tfvars

tf-apply: ## Terraform 应用
	cd terraform && terraform apply -var-file=terraform.tfvars

tf-destroy: ## Terraform 销毁
	cd terraform && terraform destroy -var-file=terraform.tfvars

# --------------------------------------------------
# 验证
# --------------------------------------------------
validate: ## 验证所有配置文件
	@echo "=== Docker Compose ==="
	cd docker && docker compose -f docker-compose.yml config > /dev/null
	@echo "=== K8s kubeconform ==="
	kubeconform -kubernetes-version 1.30.0 -strict -summary k8s/
	@echo "=== Helm Lint ==="
	helm lint helm/accounting-platform
	@echo "=== 全部通过 ==="

lint: ## 代码检查（pre-commit）
	pre-commit run --all-files
