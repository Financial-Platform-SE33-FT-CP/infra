# 会计平台 — 基础设施

## 概述

本目录包含会计平台微服务的基础设施配置。平台基于 Docker Compose 运行，包含 PostgreSQL
数据库、Redis 缓存、六个 Python 微服务、一个前端应用及 Nginx 反向代理。

## 快速开始

```bash
# 启动所有服务
docker compose -f docker/docker-compose.yml up -d

# 开发模式（热重载、调试）
docker compose -f docker/docker-compose.yml -f docker/docker-compose.dev.yml up -d

# 查看日志
docker compose -f docker/docker-compose.yml logs -f

# 停止所有服务
docker compose -f docker/docker-compose.yml down

# 停止并删除数据卷
docker compose -f docker/docker-compose.yml down -v
```

## 服务映射

| 服务              | 端口  | 说明                                            |
|-------------------|-------|-------------------------------------------------|
| **Nginx**         | 80    | 反向代理，将 /api/* 路由到各服务                |
| **Frontend**      | 3000  | Web 前端 — 通过 / 访问                          |
| **Auth Service**  | 8001  | 认证与授权 — 代理到 /api/auth/                   |
| **Tenant Service**| 8002  | 多租户管理 — 代理到 /api/tenants/                |
| **COA Service**   | 8003  | 科目表管理 — 代理到 /api/coa/                    |
| **Ledger Service**| 8004  | 总账 — 代理到 /api/ledger/                       |
| **Audit Service** | 8005  | 审计日志 — 代理到 /api/audit/                    |
| **AR/AP Service** | 8006  | 应收应付 — 代理到 /api/ar-ap/                    |
| **PostgreSQL**    | 5432  | 主数据库                                        |
| **Redis**         | 6379  | 缓存与消息队列                                   |

## 网络拓扑

```
                    ┌─────────────┐
                    │   Nginx     │  :80
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
      │ :8001     │  │ :8003      │  │ :8004       │
      ├───────────┤  ├────────────┤  ├─────────────┤
      │ ten-svc   │  │ audit-svc  │  │ ar-ap-svc   │
      │ :8002     │  │ :8005      │  │ :8006       │
      └─────┬─────┘  └─────┬──────┘  └──────┬──────┘
            │              │                │
            └──────────────┼────────────────┘
                           │
                    ┌──────┴──────┐
                    │  PostgreSQL │
                    └─────────────┘

                    ┌─────────────┐
                    │    Redis    │
                    └─────────────┘

                    ┌─────────────┐
                    │  Frontend   │
                    │  :3000      │
                    └─────────────┘
```

## 目录结构

```
infra/
├── README.md / README_CN.md
├── docker/
│   ├── docker-compose.yml       # 生产环境编排
│   └── docker-compose.dev.yml   # 开发环境覆盖配置
├── nginx/
│   └── default.conf             # 反向代理配置
└── .github/
    └── workflows/
        ├── ci-auth-service.yml
        ├── ci-tenant-service.yml
        ├── ci-coa-service.yml
        ├── ci-frontend.yml
        └── ci-shared-lib.yml
```

## CI/CD

每个微服务在 GitHub Actions 中均有对应的工作流，在推送到对应目录时自动触发。
Python 工作流运行 Ruff、Mypy 及 Pytest。前端工作流运行 Lint、类型检查及构建。

## 环境变量

| 变量              | 说明                              |
|-------------------|-----------------------------------|
| `DATABASE_URL`    | PostgreSQL 连接字符串              |
| `JWT_SECRET`      | JWT 签名密钥                       |
| `JWT_ALGORITHM`   | JWT 签名算法                       |
| `APP_ENV`         | 运行环境（development / production）|
| `DEBUG`           | 调试模式开关                       |
