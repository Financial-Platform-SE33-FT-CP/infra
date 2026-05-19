# 会计平台 — 基础设施

## 概述

本目录包含会计平台微服务的完整基础设施配置。平台基于 **Docker Swarm** 集群运行（已从 Kubernetes 迁移），
包含 PostgreSQL 数据库、Redis 缓存、六个 Python 微服务、一个前端应用、Nginx 反向代理，
以及完整的可观测性栈（Prometheus + Grafana + Loki）。

---

## 目录结构

```
infra/
├── README.md / README_CN.md
├── Makefile                            # 统一运维命令
├── .gitignore                          # 忽略敏感文件
├── docker/                             # Docker Compose（本地开发）
│   ├── docker-compose.yml
│   ├── docker-compose.dev.yml
│   └── docker-compose.observability.yml
├── swarm/                              # Docker Swarm（集群生产环境）
│   ├── docker-compose.swarm.yml        # 主 Stack 文件
│   ├── docker-compose.swarm.observability.yml
│   ├── env.swarm.template              # 环境变量模板（敏感）
│   ├── configs/
│   │   ├── nginx-default.conf          # Nginx 反向代理配置
│   │   └── crontab.example             # 宿主机定时备份示例
│   └── scripts/
│       ├── init-secrets.sh             # 初始化 Docker Secrets
│       ├── deploy-swarm.sh             # 部署 Stack
│       ├── verify-swarm.sh             # 验证部署状态
│       ├── run-backup.sh               # 手动执行数据库备份
│       └── swarm-autoscale.sh          # 简易自动扩缩容示例
├── nginx/
│   └── default.conf                    # 反向代理配置（参考）
├── observability/
│   ├── prometheus/prometheus.yml       # 服务发现与抓取配置
│   ├── grafana/provisioning/           # 数据源与仪表板配置
│   ├── loki/loki-config.yml
│   └── promtail/promtail-config.yml
└── archive/                            # 已归档的旧配置（K8s/Helm/Terraform）
    ├── k8s/
    ├── helm/
    ├── terraform/
    └── pg-backup-k8s.yml
```

---

## 快速开始

### 前置条件

- Docker 24.0+ 与 Docker Compose 2.20+
- 至少 1 个 Swarm Manager 节点 + 1 个 Worker 节点（生产推荐 3 Manager）
- 共享存储（NFS/Ceph/GlusterFS）或带 `storage=persistent` 标签的数据节点

### 方式一：本地开发（Docker Compose）

```bash
cd infra
make docker-dev      # 热重载、调试日志
make docker-obs      # 启动可观测性栈
make docker-down     # 停止
```

### 方式二：生产集群（Docker Swarm）

```bash
cd infra

# 1. 初始化 Swarm（Manager 节点）
make swarm-init      # 按提示执行 docker swarm init

# 2. 标记数据节点（在存储节点上执行）
docker node update --label-add storage=persistent <NODE-ID>

# 3. 创建 Secrets
cd swarm && ./scripts/init-secrets.sh

# 4. 配置环境变量
cp swarm/env.swarm.template swarm/env.swarm
# 编辑 env.swarm 填入真实值
source swarm/env.swarm

# 5. 部署 Stack
make swarm-deploy

# 6. （可选）部署可观测性栈
make swarm-deploy-obs

# 7. 验证
make swarm-ps
./swarm/scripts/verify-swarm.sh
```

---

## 服务映射

| 服务              | Swarm 端口 | 本地端口 | 说明                              |
|-------------------|------------|----------|-----------------------------------|
| **Nginx**         | 80/443     | 80/443   | 反向代理，Swarm Routing Mesh      |
| **Frontend**      | 3000       | 3000     | Next.js Web 前端                  |
| **Auth Service**  | 8000       | 8001     | 认证与授权 — /api/auth/           |
| **Tenant Service**| 8000       | 8002     | 多租户管理 — /api/tenants/        |
| **COA Service**   | 8000       | 8003     | 科目表管理 — /api/coa/            |
| **Ledger Service**| 8000       | 8004     | 总账 — /api/ledger/               |
| **Audit Service** | 8000       | 8005     | 审计日志 — /api/audit/            |
| **AR/AP Service** | 8000       | 8006     | 应收应付 — /api/ar-ap/            |
| **PostgreSQL**    | 5432       | 5432     | 主数据库，placement 约束固定节点  |
| **Redis**         | 6379       | 6379     | 缓存与消息队列                    |
| **Prometheus**    | 9090       | 9090     | 指标采集（manager 节点）          |
| **Grafana**       | 3000       | 3001     | 可视化仪表板（manager 节点）      |
| **Loki**          | 3100       | 3100     | 日志聚合（manager 节点）          |

---

## Docker Swarm 部署详解

### 初始化集群

```bash
# Manager 节点
docker swarm init --advertise-addr <MANAGER-IP>

# 获取加入令牌
docker swarm join-token worker

# Worker 节点执行
docker swarm join --token <TOKEN> <MANAGER-IP>:2377
```

### 标记数据节点

postgres 和 redis 需要持久化存储，通过 placement constraint 固定运行：

```bash
docker node update --label-add storage=persistent <NODE-ID>
```

如果使用 NFS 共享存储，可移除此约束，但建议仍约束到性能较好的节点。

### 创建 Secrets

```bash
cd swarm
./scripts/init-secrets.sh
```

交互式创建以下 Secrets：
- `database_url` — 数据库连接字符串
- `postgres_password` — PostgreSQL 密码
- `jwt_secret` — JWT 签名密钥
- `grafana_admin_password` — Grafana 管理员密码

**注意**：Docker Secret 一旦创建不可修改，只能删除重建（需先删除引用该 secret 的所有服务）。

### 配置环境变量

```bash
cp swarm/env.swarm.template swarm/env.swarm
# 编辑填入真实值
source swarm/env.swarm
```

### 部署 Stack

```bash
make swarm-deploy
# 或手动执行:
# cd swarm && ./scripts/deploy-swarm.sh
```

### 部署可观测性栈

```bash
make swarm-deploy-obs
```

### 查看状态

```bash
make swarm-services     # 服务列表
make swarm-ps           # 任务状态
make swarm-logs svc=auth-service   # 查看日志
```

### 手动扩缩容

Swarm 不原生支持 HPA，需手动扩缩容或使用脚本：

```bash
# 手动扩容
make swarm-scale svc=auth-service replicas=5

# 简易自动扩缩容（基于 docker stats，每 5 分钟执行一次）
*/5 * * * * /opt/accounting/infra/swarm/scripts/swarm-autoscale.sh auth-service 70 10
```

### 回滚服务

```bash
make swarm-rollback svc=auth-service
```

滚动更新失败时，Swarm 会根据 `deploy.update_config.failure_action: rollback` 自动回滚。
手动回滚用于其他场景。

---

## CI/CD

### GitHub Actions 工作流

| 工作流文件                    | 触发条件                              | 说明                                     |
|-------------------------------|---------------------------------------|------------------------------------------|
| `ci-infra.yml`                | 所有 PR / Push                        | Swarm Compose 语法校验、脚本检查         |
| `docker-build-backend.yml`    | backend 变更 / tag / main push        | Matrix 构建所有后端镜像并推送至 GHCR     |
| `docker-build-frontend.yml`   | frontend 变更 / tag / main push       | 构建前端镜像并推送至 GHCR                |

### 镜像地址

```
ghcr.io/financial-platform-se33-ft-cp/accounting-platform-auth-service:latest
ghcr.io/financial-platform-se33-ft-cp/accounting-platform-tenant-service:latest
ghcr.io/financial-platform-se33-ft-cp/accounting-platform-coa-service:latest
ghcr.io/financial-platform-se33-ft-cp/accounting-platform-ledger-service:latest
ghcr.io/financial-platform-se33-ft-cp/accounting-platform-audit-service:latest
ghcr.io/financial-platform-se33-ft-cp/accounting-platform-ar-ap-service:latest
ghcr.io/financial-platform-se33-ft-cp/accounting-platform-frontend:latest
```

---

## 监控与日志

### Prometheus

- URL: http://<MANAGER-IP>:9090
- 已配置所有后端服务 `/metrics` 端点自动抓取
- 在 Swarm 中，服务名（如 `auth-service:8000`）解析为 VIP，自动负载均衡

### Grafana

- URL: http://<MANAGER-IP>:3001
- 默认账号: `admin` / `grafana_admin_password`（通过 Docker Secret 注入）
- 已预配置 Prometheus 与 Loki 数据源

### Loki + Promtail

- Loki URL: http://<MANAGER-IP>:3100
- Promtail 以 `mode: global` 在每个节点运行（对应 K8s DaemonSet）
- 自动收集所有容器日志

---

## 备份与恢复

### 自动备份

在 Swarm Manager 节点配置宿主机 crontab：

```bash
# 复制示例配置
sudo cp infra/swarm/configs/crontab.example /etc/cron.d/accounting-backup

# 或手动编辑
crontab -e
# 添加:
0 2 * * * /opt/accounting/infra/swarm/scripts/run-backup.sh >> /var/log/accounting-backup.log 2>&1
```

保留策略：自动清理 7 天前的旧备份。

### 手动备份

```bash
make swarm-backup
# 或:
cd swarm && ./scripts/run-backup.sh
```

### 恢复备份

```bash
# 在任意可访问 swarm network 的节点执行
docker run --rm \
  --network accounting-platform_accounting-network \
  --secret postgres_password \
  -v /path/to/backups:/backups \
  postgres:17-alpine sh -c '
    export PGPASSWORD=$(cat /run/secrets/postgres_password)
    gunzip < /backups/accounting_YYYYMMDD_HHMMSS.sql.gz | psql -h postgres -U accounting -d accounting
  '
```

---

## 环境变量

| 变量                          | 来源                    | 说明                              |
|-------------------------------|-------------------------|-----------------------------------|
| `DATABASE_URL`                | `env.swarm`             | SQLAlchemy 连接字符串              |
| `JWT_SECRET`                  | `env.swarm`             | JWT 签名密钥                       |
| `POSTGRES_PASSWORD`           | Docker Secret           | PostgreSQL 密码（通过 *_FILE 注入）|
| `GRAFANA_ADMIN_PASSWORD`      | Docker Secret           | Grafana 密码（通过 *_FILE 注入）   |
| `APP_ENV`                     | compose 文件            | 运行环境                           |
| `LOG_LEVEL`                   | compose 文件            | 日志级别                           |
| `JWT_ALGORITHM`               | compose 文件            | JWT 签名算法                       |
| `REDIS_URL`                   | compose 文件            | Redis 连接字符串                   |
| `AUTH_SERVICE_URL`            | compose 文件            | 认证服务内部地址                   |
| `CORS_ORIGINS`                | compose 文件            | 允许的前端地址                     |

---

## 网络拓扑（Swarm 模式）

```
              ┌─────────────────────────────────────┐
              │      Docker Swarm Routing Mesh      │
              │         任意节点 :80 / :443         │
              └───────────────┬─────────────────────┘
                              │
                    ┌─────────┴────────┐
                    │      Nginx       │  (replicas: 2)
                    │   Load Balancer  │
                    └─────────┬────────┘
                              │
        ┌─────────┬───────────┼───────────┬───────────┐
        │         │           │           │           │
   ┌────┴───┐ ┌───┴────┐ ┌───┴────┐ ┌───┴────┐ ┌────┴───┐
   │/api/auth│ │/api/ten│ │/api/coa│ │/api/led│ │/api/...│
   └────┬───┘ └───┬────┘ └───┬────┘ └───┬────┘ └────┬───┘
        │         │          │          │           │
   ┌────┴───┐ ┌───┴────┐ ┌───┴────┐ ┌───┴────┐ ┌────┴───┐
   │ auth   │ │ tenant │ │  coa   │ │ ledger │ │  ...   │
   │(2 repl)│ │(2 repl)│ │(2 repl)│ │(2 repl)│ │(2 repl)│
   └────┬───┘ └───┬────┘ └───┬────┘ └───┬────┘ └────┬───┘
        │         │          │          │           │
        └─────────┴──────────┴────┬─────┴───────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │      accounting-network   │
                    │      (overlay, encrypted) │
                    └─────────────┬─────────────┘
                                  │
                    ┌─────────────┼─────────────┐
                    │             │             │
              ┌─────┴─────┐ ┌────┴────┐ ┌─────┴─────┐
              │ PostgreSQL│ │  Redis  │ │  Frontend │
              │(1 repl,  │ │(1 repl, │ │(2 repl)  │
              │placement) │ │placement)│ │           │
              └───────────┘ └─────────┘ └───────────┘
```

---

## 注意事项

1. **JWT_SECRET** 和 **POSTGRES_PASSWORD** 在生产环境中必须使用强密码，切勿使用默认值。
2. **Docker Secrets**: 敏感信息已迁移至 Docker Secrets，宿主机 `.env.swarm` 仍需保护，不应提交到版本库（已加入 `.gitignore`）。
3. **持久化存储**: postgres 和 redis 通过 `node.labels.storage == persistent` 约束固定到数据节点。生产环境强烈建议使用 NFS/Ceph 等共享存储，避免单点故障导致数据丢失。
4. **HPA 替代**: Docker Swarm 不支持原生水平自动扩缩容。已提供 `swarm-autoscale.sh` 示例脚本，生产环境建议基于 Prometheus 指标构建更完善的自动扩缩容方案。
5. **Network Policy 替代**: Swarm 的 overlay 网络默认隔离不同 stack。如需更细粒度的网络隔离，可使用 `--opt encrypted`（已启用）或考虑创建多个 overlay network。
6. **RBAC 替代**: Swarm 没有 K8s 级别的 RBAC。访问控制通过 Docker API TLS 证书和节点角色（Manager/Worker）实现。生产环境建议限制 Manager 节点访问权限。
7. **Ingress 替代**: Swarm 使用 Routing Mesh + Nginx Service 替代 K8s Ingress。如需更高级的路由功能（自动证书、灰度发布），可迁移至 Traefik。
8. **滚动更新与回滚**: 所有服务已配置 `update_config` 和 `rollback_config`，更新失败会自动回滚到上一个稳定版本。
9. **健康检查**: 所有后端服务均已配置 `/health` 端点，Swarm 会结合健康检查进行滚动更新调度。
10. **多节点日志**: Promtail 以 `global` 模式在每个节点运行，确保收集整个集群的容器日志。
