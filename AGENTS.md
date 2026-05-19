# Repository Guidelines

## Project Overview

Infrastructure configuration for the Accounting Platform. Manages **Docker Swarm** cluster orchestration for production, and Docker Compose for local development. The platform runs 6 backend microservices (single Dockerfile with `SERVICE` build arg), a Next.js frontend, PostgreSQL, Redis, Nginx reverse proxy, and an observability stack (Prometheus + Grafana + Loki + Promtail).

**Note**: Kubernetes manifests, Helm charts, and Terraform modules have been archived to `archive/` and replaced with Docker Swarm configurations in `swarm/`.

## Architecture & Data Flow

```
Internet
  → Nginx (:80)  [Swarm Routing Mesh — any node]
    ├── /api/auth/*     → auth-service:8000
    ├── /api/tenants/*  → tenant-service:8000
    ├── /api/coa/*      → coa-service:8000
    ├── /api/ledger/*   → ledger-service:8000
    ├── /api/audit/*    → audit-service:8000
    ├── /api/ar-ap/*    → ar-ap-service:8000
    └── /               → frontend:3000
        All backend services → PostgreSQL:5432
        Optional: → Redis:6379
```

### Service-Port Mapping

| Service | Internal Port | External Port | Nginx Route | Swarm Replicas |
|---------|--------------|---------------|-------------|----------------|
| Nginx | 80 | 80 | — | 2 |
| Frontend | 3000 | 3000 | `/` | 2 |
| Auth Service | 8000 | — | `/api/auth/` | 2 |
| Tenant Service | 8000 | — | `/api/tenants/` | 2 |
| COA Service | 8000 | — | `/api/coa/` | 2 |
| Ledger Service | 8000 | — | `/api/ledger/` | 2 |
| Audit Service | 8000 | — | `/api/audit/` | 2 |
| AR/AP Service | 8000 | — | `/api/ar-ap/` | 2 |
| PostgreSQL | 5432 | — | — | 1 (constrained) |
| Redis | 6379 | — | — | 1 (constrained) |

All backend services listen on port 8000 internally. In Swarm mode, external ports are only exposed for Nginx (80/443), Prometheus (9090), Grafana (3001), and Loki (3100). Backend services are accessed internally via the overlay network.

## Key Directories

| Directory | Purpose |
|-----------|---------|
| `swarm/` | Docker Swarm stack files, configs, secrets scripts, and deployment automation |
| `docker/` | Docker Compose files for local development (production + dev + observability) |
| `nginx/` | Nginx reverse proxy configuration (reference) |
| `observability/` | Prometheus, Grafana, Loki, Promtail configurations |
| `archive/` | Archived Kubernetes manifests, Helm charts, and Terraform modules |
| `.github/workflows/` | GitHub Actions CI pipelines |

## Development Commands

### Local Development (Docker Compose)

```bash
# Start all services (production mode)
docker compose -f docker/docker-compose.yml up -d

# Start with development overrides (bind mounts, hot reload, DEBUG=true)
docker compose -f docker/docker-compose.yml -f docker/docker-compose.dev.yml up -d

# View logs for a specific service
docker compose -f docker/docker-compose.yml logs -f auth-service

# Rebuild and restart a single service after code changes
docker compose -f docker/docker-compose.yml up -d --build auth-service

# Stop all services
docker compose -f docker/docker-compose.yml down

# Stop and remove volumes (reset database)
docker compose -f docker/docker-compose.yml down -v
```

### Production Deployment (Docker Swarm)

```bash
# Initialize secrets
cd swarm && ./scripts/init-secrets.sh

# Configure environment
cp swarm/env.swarm.template swarm/env.swarm
source swarm/env.swarm

# Deploy stack
cd swarm && ./scripts/deploy-swarm.sh

# Verify deployment
cd swarm && ./scripts/verify-swarm.sh

# View service logs
docker service logs -f accounting-platform_auth-service

# Scale a service
docker service scale accounting-platform_auth-service=5

# Rollback a service
docker service update --rollback accounting-platform_auth-service
```

### Makefile Shortcuts

```bash
make docker-dev          # Local development mode
make swarm-deploy        # Deploy to Swarm
make swarm-deploy-obs    # Deploy with observability
make swarm-ps            # View task status
make swarm-services      # List services
make swarm-scale svc=auth-service replicas=5
make validate            # Validate all compose files
```

## Code Conventions & Common Patterns

### Docker Swarm Stack (`swarm/docker-compose.swarm.yml`)

- **Network**: `accounting-network` with `driver: overlay` and `attachable: true` (encrypted)
- **PostgreSQL**: `postgres:17-alpine`, persistent volume `pgdata`, placement constrained to `node.labels.storage == persistent`, uses `POSTGRES_PASSWORD_FILE` pointing to Docker Secret
- **Redis**: `redis:7-alpine`, persistent volume `redisdata`, placement constrained to data nodes
- **Backend services**: pull from GHCR (`ghcr.io/.../accounting-platform-<service>:latest`), `deploy.replicas: 2`, spread across nodes, healthchecks via `wget` on `/health`, restart policy `any`
- **Frontend**: `ghcr.io/.../accounting-platform-frontend:latest`, `deploy.replicas: 2`
- **Nginx**: `nginx:alpine`, mounts config via Docker Config (`configs:`), exposes ports 80/443 via Swarm ingress routing mesh, `deploy.replicas: 2`
- **Secrets**: `database_url`, `postgres_password`, `jwt_secret`, `grafana_admin_password` — created via `init-secrets.sh`, referenced in services with `secrets:`
- **Rolling updates**: all services have `update_config` with `parallelism: 1`, `delay: 10s`, `failure_action: rollback`, and `rollback_config`

### Docker Compose — Production (`docker/docker-compose.yml`)

- PostgreSQL: `postgres:17-alpine` with named volume `accounting-pgdata`, healthcheck via `pg_isready`
- Redis: `redis:7-alpine`, healthcheck via `redis-cli ping`
- Backend services: single build context `../backend` with `SERVICE` build arg, depends on postgres (healthy), curl-based healthchecks on `/health`
- Frontend: build context `../frontend`, depends on all backend services (started)
- Nginx: `nginx:alpine`, mounts `nginx/default.conf` read-only
- Network: `accounting-network` (bridge driver)

### Backend Service Build Pattern

```yaml
auth-service:
  build:
    context: ../backend        # Single monorepo
    dockerfile: Dockerfile
    args:
      SERVICE: auth-service    # Selects package
  environment:
    DATABASE_URL: postgresql+asyncpg://accounting:accounting_secret@postgres:5432/accounting
```

All 6 backend services use identical build context, differing only in `SERVICE` arg and port/environment.

### Docker Compose — Development (`docker/docker-compose.dev.yml`)

Overrides for local development:
- **Bind mounts**: `../backend:/app` for live code updates
- **Environment**: `APP_ENV=development`, `DEBUG=true`, `LOG_LEVEL=DEBUG`
- **Hot reload**: `uv run --package <svc> uvicorn <svc>.main:app --reload`
- **Frontend**: `npm run dev` with bind mount

### Nginx Reverse Proxy

Each backend service gets a `location` block:

```nginx
location /api/auth/ {
    proxy_pass http://auth-service:8000/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

In Swarm mode, service names (`auth-service`, `frontend`, etc.) resolve to the service VIP via the embedded DNS server, providing automatic load balancing across replicas.

### CI/CD Pipeline Pattern

All Python workflows follow the same pattern:

```yaml
name: CI — <service>
on:
  push:
    paths: ['<relevant-path>/**']
  pull_request:
    paths: ['<relevant-path>/**']
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - run: pip install uv && uv sync
      - run: uv run ruff check
      - run: uv run mypy
      - run: uv run pytest
```

Frontend CI uses Node.js 22: `npm ci` → `npm run lint` → `npm run build`.

Currently implemented workflows: `ci-auth-service.yml`, `ci-tenant-service.yml`, `ci-coa-service.yml`, `ci-shared-lib.yml`, `ci-frontend.yml`, `ci-infra.yml`.

## Important Files

| File | Role |
|------|------|
| `swarm/docker-compose.swarm.yml` | Production Swarm stack definition |
| `swarm/docker-compose.swarm.observability.yml` | Observability stack for Swarm |
| `swarm/scripts/init-secrets.sh` | Interactive Docker Secret creation |
| `swarm/scripts/deploy-swarm.sh` | Stack deployment with validation |
| `swarm/scripts/verify-swarm.sh` | Post-deployment health verification |
| `swarm/configs/nginx-default.conf` | Nginx config mounted as Docker Config |
| `docker/docker-compose.yml` | Local production-like orchestration |
| `docker/docker-compose.dev.yml` | Local development overrides |
| `nginx/default.conf` | Reference reverse proxy configuration |

## Environment Variables

| Variable | Used By | Description |
|----------|---------|-------------|
| `DATABASE_URL` | All backend services | PostgreSQL connection string |
| `JWT_SECRET` | auth-service | JWT signing secret |
| `JWT_ALGORITHM` | auth-service | JWT algorithm (HS256) |
| `JWT_ACCESS_TOKEN_EXPIRE_MINUTES` | auth-service | Access token TTL |
| `APP_ENV` | All services | `development` or `production` |
| `DEBUG` | All services | Debug mode toggle |
| `LOG_LEVEL` | All services | Logging level (DEBUG/INFO/WARNING) |
| `CORS_ORIGINS` | Backend services | JSON array of allowed origins |
| `AUTH_SERVICE_URL` | tenant-service | Internal auth service URL |
| `GRAFANA_ADMIN_USER` | grafana | Grafana admin username |
| `GRAFANA_ADMIN_PASSWORD` | grafana | Grafana admin password (via secret) |
| `NEXT_PUBLIC_API_URL` | frontend | Backend API base URL |

## Swarm-Specific Considerations

- **No native HPA**: Docker Swarm does not have horizontal pod autoscaling. Use `make swarm-scale` or `swarm-autoscale.sh` for scaling. For production-grade autoscaling, integrate with Prometheus metrics and a custom controller.
- **No Ingress resources**: Swarm uses ingress routing mesh + Nginx service. Port 80/443 published on any node routes to Nginx replicas.
- **Persistent data**: PostgreSQL and Redis use placement constraints (`node.labels.storage == persistent`) to pin to data nodes. Use NFS/shared storage for high availability.
- **Secrets management**: Sensitive data is stored in Docker Secrets (encrypted at rest). Non-sensitive config is inline in compose files or via `env.swarm`.
- **Logging**: Promtail runs in `global` mode (one per node) to collect all container logs and push to Loki.
- **Backup**: CronJob equivalent is host-level crontab running `run-backup.sh`, which launches a temporary container with the postgres secret mounted.

## Runtime/Tooling Preferences

- **Orchestration**: Docker Swarm (production), Docker Compose v3.9+ (local)
- **Container base images**: `python:3.12-slim`, `postgres:17-alpine`, `redis:7-alpine`, `nginx:alpine`, `node:22-alpine`
- **CI**: GitHub Actions, `ubuntu-latest` runners
- **Python toolchain** (CI): uv → ruff → mypy → pytest
- **Node toolchain** (CI): npm ci → eslint → tsc → next build
- **Registry**: GHCR (`ghcr.io/financial-platform-se33-ft-cp/...`)
