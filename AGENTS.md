# Repository Guidelines

## Project Overview

Infrastructure configuration for the Accounting Platform. Manages Docker Compose orchestration (10 services), Nginx reverse proxy routing, and GitHub Actions CI/CD pipelines. The platform runs 6 backend microservices (single Dockerfile with `SERVICE` build arg), a Next.js frontend, PostgreSQL, and Redis behind an Nginx reverse proxy.

## Architecture & Data Flow

```
Internet
  → Nginx (:80)
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

| Service | Internal Port | External Port | Nginx Route |
|---------|--------------|---------------|-------------|
| Nginx | 80 | 80 | — |
| Frontend | 3000 | 3000 | `/` |
| Auth Service | 8000 | 8001 | `/api/auth/` |
| Tenant Service | 8000 | 8002 | `/api/tenants/` |
| COA Service | 8000 | 8003 | `/api/coa/` |
| Ledger Service | 8000 | 8004 | `/api/ledger/` |
| Audit Service | 8000 | 8005 | `/api/audit/` |
| AR/AP Service | 8000 | 8006 | `/api/ar-ap/` |
| PostgreSQL | 5432 | 5432 | — |
| Redis | 6379 | 6379 | — |

All backend services listen on port 8000 internally; external ports are offset for host access.

## Key Directories

| Directory | Purpose |
|-----------|---------|
| `docker/` | Docker Compose files (production + dev) |
| `nginx/` | Nginx reverse proxy configuration |
| `.github/workflows/` | GitHub Actions CI pipelines |

## Development Commands

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

## Code Conventions & Common Patterns

### Docker Compose — Production (`docker-compose.yml`)

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

### Docker Compose — Development (`docker-compose.dev.yml`)

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

CORS headers are set globally (`add_header Access-Control-Allow-Origin *`) and per-location for OPTIONS preflight. Frontend location includes WebSocket upgrade headers for Next.js HMR.

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

Currently implemented workflows: `ci-auth-service.yml`, `ci-tenant-service.yml`, `ci-coa-service.yml`, `ci-shared-lib.yml`, `ci-frontend.yml`.

## Important Files

| File | Role |
|------|------|
| `docker/docker-compose.yml` | Production service orchestration |
| `docker/docker-compose.dev.yml` | Development overrides (bind mounts, hot reload) |
| `nginx/default.conf` | Reverse proxy routes, CORS, WebSocket support |
| `.github/workflows/ci-auth-service.yml` | Auth service CI pipeline |
| `.github/workflows/ci-tenant-service.yml` | Tenant service CI pipeline |
| `.github/workflows/ci-coa-service.yml` | COA service CI pipeline |
| `.github/workflows/ci-shared-lib.yml` | Shared library CI pipeline |
| `.github/workflows/ci-frontend.yml` | Frontend CI pipeline |

## Environment Variables

| Variable | Used By | Description |
|----------|---------|-------------|
| `DATABASE_URL` | All backend services | PostgreSQL connection string (`postgresql+asyncpg://...`) |
| `JWT_SECRET` | auth-service | JWT signing secret |
| `JWT_ALGORITHM` | auth-service | JWT algorithm (HS256) |
| `JWT_ACCESS_TOKEN_EXPIRE_MINUTES` | auth-service | Access token TTL |
| `APP_ENV` | All services | `development` or `production` |
| `DEBUG` | All services | Debug mode toggle |
| `LOG_LEVEL` | All services | Logging level (DEBUG/INFO/WARNING) |
| `CORS_ORIGINS` | Backend services | JSON array of allowed origins |
| `AUTH_SERVICE_URL` | tenant-service | Internal auth service URL |
| `NEXT_PUBLIC_API_URL` | frontend | Backend API base URL |

## Runtime/Tooling Preferences

- **Orchestration**: Docker Compose v3.9+
- **Container base images**: `python:3.12-slim`, `postgres:17-alpine`, `redis:7-alpine`, `nginx:alpine`, `node:22-alpine`
- **CI**: GitHub Actions, `ubuntu-latest` runners
- **Python toolchain** (CI): uv → ruff → mypy → pytest
- **Node toolchain** (CI): npm ci → eslint → tsc → next build
