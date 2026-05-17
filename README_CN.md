# 会计平台 — 基础设施

## 概述

本目录包含会计平台微服务的完整基础设施配置。平台基于 Docker Compose 和 Kubernetes 双模式运行，
包含 PostgreSQL 数据库、Redis 缓存、六个 Python 微服务、一个前端应用、Nginx 反向代理，
以及完整的可观测性栈（Prometheus + Grafana + Loki）。

---

## 目录结构

```
infra/
├── README.md / README_CN.md
├── docker/
│   ├── docker-compose.yml              # 生产环境编排
│   ├── docker-compose.dev.yml          # 开发环境覆盖配置
│   └── docker-compose.backup.yml       # 数据库备份（profile: backup）
├── nginx/
│   └── default.conf                    # 反向代理配置（含限流、安全头）
├── k8s/                                # Kubernetes manifests
│   ├── 01-namespace.yml
│   ├── 02-configmap.yml
│   ├── 03-secret.yml
│   ├── 10-postgres.yml                 # StatefulSet + Service
│   ├── 11-redis.yml                    # Deployment + Service
│   ├── 20-auth-service.yml             # Deployment + Service + HPA
│   ├── 20-tenant-service.yml
│   ├── 20-coa-service.yml
│   ├── 20-ledger-service.yml
│   ├── 20-audit-service.yml
│   ├── 20-ar-ap-service.yml
│   ├── 30-frontend.yml
│   ├── 31-nginx.yml
│   └── 40-ingress.yml
├── observability/
│   ├── prometheus/prometheus.yml       # 服务发现与抓取配置
│   ├── grafana/provisioning/           # 数据源与仪表板配置
│   ├── loki/loki-config.yml
│   └── promtail/promtail-config.yml
└── backup/
    └── pg-backup.yml                   # K8s CronJob + PVC
```

---

## 快速开始

### 前置条件

- Docker 20.10+ 与 Docker Compose 2.20+
- 复制项目根目录 `.env.example` 为 `.env` 并修改密码

### 启动所有服务（生产模式）

```bash
cd infra/docker
docker compose up -d
```

### 开发模式（热重载、调试日志）

```bash
cd infra/docker
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

### 启动可观测性栈

```bash
cd infra/docker
docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d
```

### 手动执行数据库备份

```bash
cd infra/docker
docker compose -f docker-compose.yml -f docker-compose.backup.yml --profile backup up
```

### 停止并清理

```bash
docker compose -f docker-compose.yml down
# 停止并删除数据卷（彻底清理）
docker compose -f docker-compose.yml down -v
```

---

## 服务映射

| 服务              | 容器端口 | 主机端口 | 说明                                            |
|-------------------|----------|----------|-------------------------------------------------|
| **Nginx**         | 80/443   | 80/443   | 反向代理，限流、安全头、CORS                    |
| **Frontend**      | 3000     | 3000     | Next.js Web 前端                                |
| **Auth Service**  | 8000     | 8001     | 认证与授权 — 代理到 /api/auth/                  |
| **Tenant Service**| 8000     | 8002     | 多租户管理 — 代理到 /api/tenants/               |
| **COA Service**   | 8000     | 8003     | 科目表管理 — 代理到 /api/coa/                   |
| **Ledger Service**| 8000     | 8004     | 总账 — 代理到 /api/ledger/                      |
| **Audit Service** | 8000     | 8005     | 审计日志 — 代理到 /api/audit/                   |
| **AR/AP Service** | 8000     | 8006     | 应收应付 — 代理到 /api/ar-ap/                   |
| **PostgreSQL**    | 5432     | 5432     | 主数据库，带健康检查与资源限制                   |
| **Redis**         | 6379     | 6379     | 缓存与消息队列，AOF 持久化                       |
| **Prometheus**    | 9090     | 9090     | 指标采集与告警                                   |
| **Grafana**       | 3000     | 3001     | 可视化仪表板                                     |
| **Loki**          | 3100     | 3100     | 日志聚合                                         |

---

## Kubernetes 部署

### 前置条件

- Kubernetes 1.28+
- kubectl 已配置
- Ingress Controller（如 nginx-ingress）已安装
- cert-manager（如需自动 TLS）

### 部署步骤

```bash
cd infra/k8s

# 1. 创建命名空间
kubectl apply -f 01-namespace.yml

# 2. 创建 ConfigMap
kubectl apply -f 02-configmap.yml

# 3. 创建 Secret（编辑 03-secret.yml 填入真实密码后再执行）
kubectl apply -f 03-secret.yml

# 4. 部署数据层
kubectl apply -f 10-postgres.yml -f 11-redis.yml

# 5. 部署后端微服务
kubectl apply -f 20-auth-service.yml -f 20-tenant-service.yml \
  -f 20-coa-service.yml -f 20-ledger-service.yml \
  -f 20-audit-service.yml -f 20-ar-ap-service.yml

# 6. 部署前端与网关
kubectl apply -f 30-frontend.yml -f 31-nginx.yml

# 7. 配置 Ingress（修改 40-ingress.yml 中的域名）
kubectl apply -f 40-ingress.yml

# 8. 启用备份
kubectl apply -f ../backup/pg-backup.yml
```

### 查看状态

```bash
kubectl get pods -n accounting-platform
kubectl get svc -n accounting-platform
kubectl get hpa -n accounting-platform
kubectl logs -f deployment/auth-service -n accounting-platform
```

### 扩缩容

HPA 已默认启用，CPU 利用率 70% 或内存利用率 80% 时自动扩容，
副本数范围 2-10。手动调整：

```bash
kubectl scale deployment auth-service --replicas=5 -n accounting-platform
```

---

## CI/CD

### GitHub Actions 工作流

工作流位于仓库根目录 `.github/workflows/`：

| 工作流文件                    | 触发条件                              | 说明                                     |
|-------------------------------|---------------------------------------|------------------------------------------|
| `ci-root.yml`                 | 所有 PR / Push                        | pre-commit 检查、工作流语法校验          |
| `ci-shared-lib.yml`           | shared-lib 变更                       | ruff、mypy、pytest 单元测试              |
| `ci-auth-service.yml`         | auth-service / shared-lib 变更        | 代码检查 + 单元测试 + Testcontainers 集成测试 |
| `ci-tenant-service.yml`       | tenant-service / shared-lib 变更      | 同上                                     |
| `ci-coa-service.yml`          | coa-service / shared-lib 变更         | 同上                                     |
| `ci-ledger-service.yml`       | ledger-service / shared-lib 变更      | 同上                                     |
| `ci-audit-service.yml`        | audit-service / shared-lib 变更       | 同上                                     |
| `ci-ar-ap-service.yml`        | ar-ap-service / shared-lib 变更       | 同上                                     |
| `ci-frontend.yml`             | frontend 变更                         | lint、type-check、vitest 单元测试、build |
| `docker-build-backend.yml`    | backend 变更 / tag / main push        | Matrix 构建所有后端镜像并推送至 GHCR     |
| `docker-build-frontend.yml`   | frontend 变更 / tag / main push       | 构建前端镜像并推送至 GHCR                |
| `release.yml`                 | Git Tag `v*`                          | 自动生成 Release Notes 与镜像清单        |

### 镜像地址

```
ghcr.io/<OWNER>/accounting-platform-auth-service:<tag>
ghcr.io/<OWNER>/accounting-platform-tenant-service:<tag>
ghcr.io/<OWNER>/accounting-platform-coa-service:<tag>
ghcr.io/<OWNER>/accounting-platform-ledger-service:<tag>
ghcr.io/<OWNER>/accounting-platform-audit-service:<tag>
ghcr.io/<OWNER>/accounting-platform-ar-ap-service:<tag>
ghcr.io/<OWNER>/accounting-platform-frontend:<tag>
```

### 覆盖率要求

- 后端单元测试：覆盖率阈值 **75%**，低于阈值 CI 失败
- 前端单元测试：行覆盖率、分支覆盖率、函数覆盖率均 **75%**

---

## 监控与日志

### Prometheus

- URL: http://localhost:9090
- 已配置所有后端服务 `/metrics` 端点自动抓取
- 如需暴露 FastAPI 指标，在各服务中添加 `prometheus-fastapi-instrumentator` 依赖

### Grafana

- URL: http://localhost:3001
- 默认账号: `admin` / `.env` 中配置的 `GRAFANA_ADMIN_PASSWORD`
- 已预配置 Prometheus 与 Loki 数据源

### Loki + Promtail

- Loki URL: http://localhost:3100
- Promtail 自动收集所有带 `logging=promtail` 标签的容器日志
- 为服务添加标签：`docker compose` 中设置 `labels: - logging=promtail`

---

## 备份与恢复

### 自动备份（Kubernetes）

CronJob 每天凌晨 2 点执行（北京时间），保留最近 7 天备份。

```bash
# 查看备份历史
kubectl get cronjobs -n accounting-platform
kubectl get jobs -n accounting-platform

# 手动触发备份
kubectl create job --from=cronjob/postgres-backup manual-backup-$(date +%s) -n accounting-platform

# 查看备份文件
kubectl exec -it deployment/postgres -n accounting-platform -- ls /backups
```

### 恢复备份

```bash
# 进入 postgres 容器
kubectl exec -it deployment/postgres -n accounting-platform -- bash

# 恢复指定备份
gunzip < /backups/accounting_YYYYMMDD_HHMMSS.sql.gz | psql -U accounting -d accounting
```

### Docker Compose 备份

```bash
cd infra/docker
docker compose -f docker-compose.yml -f docker-compose.backup.yml --profile backup up
ls backups/
```

---

## 环境变量

| 变量                          | 默认值 / 示例                              | 说明                              |
|-------------------------------|--------------------------------------------|-----------------------------------|
| `POSTGRES_USER`               | `accounting`                               | PostgreSQL 用户名                  |
| `POSTGRES_PASSWORD`           | `change_me_in_production`                  | PostgreSQL 密码（必须修改）        |
| `POSTGRES_DB`                 | `accounting`                               | PostgreSQL 数据库名                |
| `DATABASE_URL`                | `postgresql+asyncpg://...`                 | SQLAlchemy 连接字符串              |
| `REDIS_URL`                   | `redis://redis:6379/0`                     | Redis 连接字符串                   |
| `JWT_SECRET`                  | `change_me_in_production`                  | JWT 签名密钥（必须修改）           |
| `JWT_ALGORITHM`               | `HS256`                                    | JWT 签名算法                       |
| `JWT_ACCESS_TOKEN_EXPIRE_MINUTES` | `30`                                   | Access Token 过期时间（分钟）      |
| `APP_ENV`                     | `production`                               | 运行环境                           |
| `LOG_LEVEL`                   | `INFO`                                     | 日志级别                           |
| `CORS_ORIGINS`                | `["http://localhost:3000"]`                | 允许的前端地址                     |
| `AUTH_SERVICE_URL`            | `http://auth-service:8000`                 | 认证服务内部地址                   |
| `GRAFANA_ADMIN_USER`          | `admin`                                    | Grafana 管理员账号                 |
| `GRAFANA_ADMIN_PASSWORD`      | `change_me_in_production`                  | Grafana 管理员密码（必须修改）     |

---

## 网络拓扑

```
                    ┌─────────────┐
                    │   Ingress   │  :443
                    │   / Nginx   │  :80
                    └─────┬───────┘
                          │
            ┌─────────────┼─────────────────┐
            │             │                 │
      ┌─────┴─────┐  ┌───┴──────┐   ┌─────┴──────┐
      │ /api/auth │  │ /api/coa │   │ /api/ledger│
      │ /api/ten. │  │ etc.     │   │            │
      └─────┬─────┘  └───┬──────┘   └─────┬──────┘
            │             │                 │
      ┌─────┴─────┐  ┌───┴────────┐  ┌────┴────────┐
      │ auth-svc  │  │ coa-svc    │  │ ledger-svc  │
      │ (2 repl.) │  │ (2 repl.)  │  │ (2 repl.)   │
      ├───────────┤  ├────────────┤  ├─────────────┤
      │ ten-svc   │  │ audit-svc  │  │ ar-ap-svc   │
      │ (2 repl.) │  │ (2 repl.)  │  │ (2 repl.)   │
      └─────┬─────┘  └─────┬──────┘  └──────┬──────┘
            │              │                │
            └──────────────┼────────────────┘
                           │
                    ┌──────┴──────┐
                    │  PostgreSQL │
                    │  StatefulSet│
                    └─────────────┘
                    ┌─────────────┐
                    │    Redis    │
                    └─────────────┘
                    ┌─────────────┐
                    │  Frontend   │
                    │  (2 repl.)  │
                    └─────────────┘
```

---

## 注意事项

1. **JWT_SECRET** 和 **POSTGRES_PASSWORD** 在生产环境中必须使用强密码，切勿使用默认值。
2. **HTTPS**: Docker Compose 环境中默认仅暴露 HTTP 端口。生产环境建议在前方放置 Cloudflare、AWS ALB 或自行配置 TLS 证书。
3. **K8s Secret**: `03-secret.yml` 中的值为占位符，部署前务必替换为真实值，并建议使用 Sealed Secrets 或 External Secrets Operator 管理。
4. **资源限制**: Docker Compose 和 K8s 中均已配置 CPU/内存限制，请根据实际负载调整。
5. **健康检查**: 所有后端服务均已配置 `/health` 端点探针，确保服务就绪后才接收流量。
