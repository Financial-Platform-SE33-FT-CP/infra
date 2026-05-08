# Accounting Platform — Infrastructure

## Overview

This directory contains the infrastructure configuration for the Accounting
Platform microservices. The platform runs on Docker Compose with a PostgreSQL
database, Redis cache, six Python microservices, one frontend application, and
an Nginx reverse proxy.

## Quick Start

```bash
# Start all services
docker compose -f docker/docker-compose.yml up -d

# Start with development overrides (hot reload, debug)
docker compose -f docker/docker-compose.yml -f docker/docker-compose.dev.yml up -d

# View logs
docker compose -f docker/docker-compose.yml logs -f

# Stop all services
docker compose -f docker/docker-compose.yml down

# Stop and remove volumes
docker compose -f docker/docker-compose.yml down -v
```

## Service Map

| Service         | Port  | Description                                      |
|-----------------|-------|--------------------------------------------------|
| **Nginx**       | 80    | Reverse proxy, routes /api/* to services         |
| **Frontend**    | 3000  | Web UI — proxied at /                            |
| **Auth Service**| 8001  | Authentication & authorization — proxied at /api/auth/ |
| **Tenant Service**| 8002| Multi-tenant management — proxied at /api/tenants/  |
| **COA Service** | 8003  | Chart of Accounts — proxied at /api/coa/         |
| **Ledger Service**| 8004 | General ledger — proxied at /api/ledger/         |
| **Audit Service**| 8005 | Audit logging — proxied at /api/audit/           |
| **AR/AP Service**| 8006 | Accounts receivable/payable — proxied at /api/ar-ap/ |
| **PostgreSQL**  | 5432  | Primary database                                 |
| **Redis**       | 6379  | Cache & message broker                           |

## Network Diagram

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

## Directory Layout

```
infra/
├── README.md
├── docker/
│   ├── docker-compose.yml       # Production compose
│   └── docker-compose.dev.yml   # Development overrides
├── nginx/
│   └── default.conf             # Reverse proxy config
└── .github/
    └── workflows/
        ├── ci-auth-service.yml
        ├── ci-tenant-service.yml
        ├── ci-coa-service.yml
        ├── ci-frontend.yml
        └── ci-shared-lib.yml
```

## CI/CD

Each microservice has a GitHub Actions workflow that runs on pushes and pull
requests affecting its directory. The Python workflows run Ruff, Black, isort,
mypy, and pytest. The frontend workflow runs lint, type-check, and build.

## Environment Variables

Key environment variables used by the services:

| Variable          | Description                        |
|-------------------|------------------------------------|
| `DATABASE_URL`    | PostgreSQL connection string       |
| `SECRET_KEY`      | JWT signing secret                 |
| `ALGORITHM`       | JWT signing algorithm              |
| `APP_ENV`         | Application environment            |
| `DEBUG`           | Debug mode flag                    |
