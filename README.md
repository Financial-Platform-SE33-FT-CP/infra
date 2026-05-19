# Accounting Platform — Infrastructure

## Overview

This directory contains the complete infrastructure configuration for the Accounting Platform microservices. The platform runs on **Docker Swarm** (migrated from Kubernetes) and includes a PostgreSQL database, Redis cache, six Python microservices, a Next.js frontend, Nginx reverse proxy, and a full observability stack (Prometheus + Grafana + Loki + Promtail).

---

## Directory Structure

```
infra/
├── README.md / README_CN.md
├── Makefile                            # Unified ops commands
├── .gitignore                          # Ignore sensitive files
├── docker/                             # Docker Compose (local development)
│   ├── docker-compose.yml
│   ├── docker-compose.dev.yml
│   └── docker-compose.observability.yml
├── swarm/                              # Docker Swarm (production cluster)
│   ├── docker-compose.swarm.yml        # Main stack file
│   ├── docker-compose.swarm.observability.yml
│   ├── env.swarm.template              # Environment variable template (sensitive)
│   ├── configs/
│   │   ├── nginx-default.conf          # Nginx reverse proxy config
│   │   └── crontab.example             # Host crontab backup example
│   └── scripts/
│       ├── init-secrets.sh             # Initialize Docker Secrets
│       ├── deploy-swarm.sh             # Deploy stack
│       ├── verify-swarm.sh             # Verify deployment status
│       ├── run-backup.sh               # Manual database backup
│       └── swarm-autoscale.sh          # Simple autoscaling example
├── nginx/
│   └── default.conf                    # Reverse proxy config (reference)
├── observability/
│   ├── prometheus/prometheus.yml       # Service discovery & scrape config
│   ├── grafana/provisioning/           # Data sources & dashboards
│   ├── loki/loki-config.yml
│   └── promtail/promtail-config.yml
└── archive/                            # Archived legacy configs (K8s/Helm/Terraform)
    ├── k8s/
    ├── helm/
    ├── terraform/
    └── pg-backup-k8s.yml
```

---

## Quick Start

### Prerequisites

- Docker 24.0+ and Docker Compose 2.20+
- At least 1 Swarm Manager node + 1 Worker node (3 Managers recommended for production)
- Shared storage (NFS/Ceph/GlusterFS) or data nodes labeled with `storage=persistent`

### Option 1: Local Development (Docker Compose)

```bash
cd infra
make docker-dev      # Hot reload, debug logs
make docker-obs      # Start observability stack
make docker-down     # Stop all services
```

### Option 2: Production Cluster (Docker Swarm)

```bash
cd infra

# 1. Initialize Swarm (on Manager node)
make swarm-init      # Follow prompts to run docker swarm init

# 2. Label data nodes (for persistent storage)
docker node update --label-add storage=persistent <NODE-ID>

# 3. Create Secrets
cd swarm && ./scripts/init-secrets.sh

# 4. Configure environment variables
cp swarm/env.swarm.template swarm/env.swarm
# Edit env.swarm with real values
source swarm/env.swarm

# 5. Deploy Stack
make swarm-deploy

# 6. (Optional) Deploy observability stack
make swarm-deploy-obs

# 7. Verify
make swarm-ps
./swarm/scripts/verify-swarm.sh
```

---

## Service Mapping

| Service           | Swarm Port | Local Port | Description                          |
|-------------------|------------|------------|--------------------------------------|
| **Nginx**         | 80/443     | 80/443     | Reverse proxy, Swarm Routing Mesh    |
| **Frontend**      | 3000       | 3000       | Next.js Web UI                       |
| **Auth Service**  | 8000       | 8001       | Authentication — /api/auth/          |
| **Tenant Service**| 8000       | 8002       | Multi-tenant — /api/tenants/         |
| **COA Service**   | 8000       | 8003       | Chart of Accounts — /api/coa/        |
| **Ledger Service**| 8000       | 8004       | General ledger — /api/ledger/        |
| **Audit Service** | 8000       | 8005       | Audit logs — /api/audit/             |
| **AR/AP Service** | 8000       | 8006       | AR/AP — /api/ar-ap/                  |
| **PostgreSQL**    | 5432       | 5432       | Primary DB, pinned to data node      |
| **Redis**         | 6379       | 6379       | Cache & message broker               |
| **Prometheus**    | 9090       | 9090       | Metrics collection (manager node)    |
| **Grafana**       | 3000       | 3001       | Dashboards (manager node)            |
| **Loki**          | 3100       | 3100       | Log aggregation (manager node)       |

---

## Docker Swarm Deployment Details

### Initialize Cluster

```bash
# Manager node
docker swarm init --advertise-addr <MANAGER-IP>

# Get join token
docker swarm join-token worker

# On worker nodes
docker swarm join --token <TOKEN> <MANAGER-IP>:2377
```

### Label Data Nodes

PostgreSQL and Redis require persistent storage and are pinned via placement constraints:

```bash
docker node update --label-add storage=persistent <NODE-ID>
```

If using NFS shared storage, this constraint can be relaxed, but it is still recommended to pin to higher-performance nodes.

### Create Secrets

```bash
cd swarm
./scripts/init-secrets.sh
```

Interactively creates the following Secrets:
- `database_url` — Database connection string
- `postgres_password` — PostgreSQL password
- `jwt_secret` — JWT signing key
- `grafana_admin_password` — Grafana admin password

**Note**: Docker Secrets are immutable. To change a secret, you must delete and recreate it (after removing all services that reference it).

### Configure Environment Variables

```bash
cp swarm/env.swarm.template swarm/env.swarm
# Edit with real values
source swarm/env.swarm
```

### Deploy Stack

```bash
make swarm-deploy
# Or manually:
# cd swarm && ./scripts/deploy-swarm.sh
```

### Deploy Observability Stack

```bash
make swarm-deploy-obs
```

### Check Status

```bash
make swarm-services     # Service list
make swarm-ps           # Task status
make swarm-logs svc=auth-service   # View logs
```

### Manual Scaling

Docker Swarm does not natively support HPA. Scale manually or use a script:

```bash
# Manual scale
make swarm-scale svc=auth-service replicas=5

# Simple autoscaling example (based on docker stats, run every 5 min)
*/5 * * * * /opt/accounting/infra/swarm/scripts/swarm-autoscale.sh auth-service 70 10
```

### Rollback

```bash
make swarm-rollback svc=auth-service
```

Swarm automatically rolls back failed deployments based on `deploy.update_config.failure_action: rollback`. Manual rollback is for other scenarios.

---

## CI/CD

### GitHub Actions Workflows

| Workflow File                 | Trigger                               | Description                          |
|-------------------------------|---------------------------------------|--------------------------------------|
| `ci-infra.yml`                | All PRs / Pushes                      | Swarm Compose validation, script linting |
| `docker-build-backend.yml`    | Backend changes / tag / main push     | Matrix build all backend images → GHCR |
| `docker-build-frontend.yml`   | Frontend changes / tag / main push    | Build frontend image → GHCR          |

### Image Registry

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

## Monitoring & Logs

### Prometheus

- URL: http://<MANAGER-IP>:9090
- Configured to scrape all backend `/metrics` endpoints
- In Swarm, service names (e.g., `auth-service:8000`) resolve to the VIP with automatic load balancing

### Grafana

- URL: http://<MANAGER-IP>:3001
- Default credentials: `admin` / `grafana_admin_password` (injected via Docker Secret)
- Pre-configured Prometheus and Loki data sources

### Loki + Promtail

- Loki URL: http://<MANAGER-IP>:3100
- Promtail runs in `global` mode (one per node, equivalent to K8s DaemonSet)
- Automatically collects all container logs

---

## Backup & Restore

### Automated Backups

Configure host-level crontab on a Swarm Manager node:

```bash
# Copy example
cp infra/swarm/configs/crontab.example /etc/cron.d/accounting-backup

# Or edit manually
crontab -e
# Add:
0 2 * * * /opt/accounting/infra/swarm/scripts/run-backup.sh >> /var/log/accounting-backup.log 2>&1
```

Retention policy: automatically deletes backups older than 7 days.

### Manual Backup

```bash
make swarm-backup
# Or:
cd swarm && ./scripts/run-backup.sh
```

### Restore from Backup

```bash
# Run on any node with access to the swarm network
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

## Environment Variables

| Variable                      | Source           | Description                          |
|-------------------------------|------------------|--------------------------------------|
| `DATABASE_URL`                | `env.swarm`      | SQLAlchemy connection string         |
| `JWT_SECRET`                  | `env.swarm`      | JWT signing secret                   |
| `POSTGRES_PASSWORD`           | Docker Secret    | PostgreSQL password (via *_FILE)     |
| `GRAFANA_ADMIN_PASSWORD`      | Docker Secret    | Grafana password (via *_FILE)        |
| `APP_ENV`                     | Compose file     | Runtime environment                  |
| `LOG_LEVEL`                   | Compose file     | Logging level                        |
| `JWT_ALGORITHM`               | Compose file     | JWT algorithm                        |
| `REDIS_URL`                   | Compose file     | Redis connection string              |
| `AUTH_SERVICE_URL`            | Compose file     | Internal auth service URL            |
| `CORS_ORIGINS`                | Compose file     | Allowed frontend origins             |

---

## Network Topology (Swarm Mode)

```
              ┌─────────────────────────────────────┐
              │      Docker Swarm Routing Mesh      │
              │         Any node :80 / :443         │
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

## Important Notes

1. **JWT_SECRET** and **POSTGRES_PASSWORD** must use strong passwords in production. Never use default values.
2. **Docker Secrets**: Sensitive data is stored in Docker Secrets (encrypted at rest). The host `.env.swarm` file must also be protected and should never be committed to version control (already in `.gitignore`).
3. **Persistent Storage**: PostgreSQL and Redis are pinned to data nodes via `node.labels.storage == persistent`. Production environments strongly recommend using NFS/Ceph or similar shared storage to avoid data loss on node failure.
4. **HPA Alternative**: Docker Swarm does not support native horizontal autoscaling. The `swarm-autoscale.sh` example script is provided. For production-grade autoscaling, integrate with Prometheus metrics and build a custom controller.
5. **Network Policy Alternative**: Swarm overlay networks are isolated by default between stacks. For finer-grained isolation, `--opt encrypted` is already enabled, or consider creating multiple overlay networks.
6. **RBAC Alternative**: Swarm lacks K8s-level RBAC. Access control relies on Docker API TLS certificates and node roles (Manager/Worker). Restrict Manager node access in production.
7. **Ingress Alternative**: Swarm uses Routing Mesh + Nginx service instead of K8s Ingress. For advanced routing (auto certificates, canary deployments), consider migrating to Traefik.
8. **Rolling Updates & Rollback**: All services are configured with `update_config` and `rollback_config`. Failed updates automatically roll back to the last stable version.
9. **Health Checks**: All backend services expose a `/health` endpoint. Swarm uses these for rolling update scheduling.
10. **Multi-node Logs**: Promtail runs in `global` mode on every node to ensure cluster-wide container log collection.
