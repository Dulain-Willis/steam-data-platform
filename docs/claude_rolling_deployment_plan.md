# Deployment Plan Implementation

## Context

The Steam Data Platform currently runs as a single-instance development stack (one Airflow webserver, one scheduler, one Spark worker). The goal is to build a full production deployment system on top of it: zero-downtime rolling deploys triggered automatically by GitHub Actions whenever code is pushed to `main` on either `steam-pipelines` or `steam-orchestration`.

---

## Current State

- `compose.yml`: single `airflow-webserver`, single `airflow-scheduler`, single `spark-worker`. No Traefik. No Airflow worker.
- Airflow runs on **LocalExecutor** — tasks execute as subprocesses inside the scheduler. No separate worker container. Restarting the scheduler during a deploy kills all in-flight tasks immediately with no way to drain them gracefully.
- `setup.sh`: clones sibling repos only. No secret generation.
- `.env.example`: no Fernet key variable.
- `steam-orchestration/.github/workflows/docker-publish.yml`: builds and pushes to GHCR. No downstream dispatch.
- `steam-pipelines/.github/workflows/docker-publish.yml`: same as above.
- No `deploy.sh`, no `traefik/`, no `.github/workflows/deploy.yml`.

---

## Implementation Steps (in order)

### Step 1 — Add Trafik service to `compose.yml`
Add Trafik service
- make container name traefik and use image traefik:v3
- Provider: Docker (socket read)
- Entrypoint: `web` on `:80`
- Dashboard on `:8090` (insecure, for debugging)
- No TLS
- `exposedByDefault: false` (only containers with `traefik.enable=true` are routed)
- Add mount `/var/run/docker.sock` read only :ro

### Step 2 — `compose.yml` (major rewrite)

Changes:
2. **Switch executor** — change `AIRFLOW__CORE__EXECUTOR` from `LocalExecutor` to `CeleryExecutor` in `x-airflow-common`. With LocalExecutor tasks run as subprocesses inside the scheduler — restarting the scheduler kills them. With CeleryExecutor tasks run in a separate worker container that can be drained gracefully before replacement.
3. **Expand `x-airflow-common` anchor** — add:
   - `AIRFLOW__CORE__FERNET_KEY: ${AIRFLOW_FERNET_KEY}`
   - `AIRFLOW__WEBSERVER__SECRET_KEY: ${AIRFLOW_SECRET_KEY}` (shared session secret needed for two webserver instances)
   - `AIRFLOW__CELERY__BROKER_URL: redis://redis:6379/0`
   - `AIRFLOW__CELERY__RESULT_BACKEND: db+postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres/${POSTGRES_DB}`
4. **Add `redis` service** — `redis:7-alpine`, no auth needed (single machine, not internet-facing). The Celery broker.
5. **Add `airflow-worker`** — permanent Celery worker service. Executes tasks. No Traefik labels. Uses the `steam-orchestration` image. Requires `apache-airflow-providers-celery` to be installed in the image (add to `steam-orchestration` requirements).
6. **Split `airflow-webserver` → `airflow-webserver-1` + `airflow-webserver-2`**:
   - webserver-1: host port `8080:8080`
   - webserver-2: host port `8082:8080`
   - webserver-2 has `profiles: [surge]` so it is only started during deploys.
   - Both carry Traefik labels: `traefik.enable=true`, router rule `Host(\`airflow.localhost\`)`, service port `8080`
7. **Split `airflow-scheduler` → `airflow-scheduler-1` + `airflow-scheduler-2`**:
   - scheduler-2 has `profiles: [surge]` so it is only started during deploys.
   - No Traefik labels.
   - With CeleryExecutor, schedulers only queue tasks — they no longer execute them. Rolling a scheduler is now safe regardless of in-flight tasks.
8. **Add `airflow-worker-surge`** — identical to `airflow-worker` but with `profiles: [surge]`. Started during deploy so there is always at least one worker running while the permanent worker drains and is replaced.
9. **Add `spark-worker-surge`** — identical to `spark-worker` but with `profiles: [surge]` so it is never started by plain `docker compose up`.
10. Keep all third-party services (postgres, minio, clickhouse, etc.) exactly as-is.

Port summary (no conflicts):
| Service | Internal port | Host port |
|---|---|---|
| traefik (Airflow UI) | 80 | 80 |
| traefik dashboard | 8090 | 8090 |
| airflow-webserver-1 | 8080 | 8080 |
| airflow-webserver-2 | 8080 | 8082 |
| spark-master UI | 8080 | 8081 |

### Step 3 — `deploy.sh` (new file)

Full rolling deploy logic, runs on the production machine. Key behaviors:

**Normal deploy (`./deploy.sh`):**

**1. Pull images from GHCR** (pre-built by GitHub Actions — no build step on the server):
```bash
docker pull ghcr.io/dulain-willis/steam-orchestration:latest
docker pull ghcr.io/dulain-willis/steam-pipelines:latest
```

**2. Capture current image digests (do not write yet)**
```bash
CURRENT_DIGESTS=$(docker inspect --format='{{.RepoDigests}}' \
  ghcr.io/dulain-willis/steam-orchestration:latest \
  ghcr.io/dulain-Willis/steam-pipelines:latest)
```

Digests are held in memory only. They are written to disk at the end of a successful deploy (step 11). If the deploy fails, the digest files are never touched — rollback always points at the last known good deploy.

On first run, if `~/.steam/deploys/` does not exist or is empty, skip the digest capture entirely — there is nothing to roll back to yet.

**3. Bring up ALL surge containers**

All services with `profiles: [surge]` start — no need to name them individually.
```bash
docker compose --profile surge up -d --no-deps
```

**4. Wait for all surge containers to report healthy via Docker healthcheck**

Poll `docker inspect --format='{{.State.Health.Status}}' <container>` == `"healthy"` for each, with its own timeout:
- `airflow-worker-surge` — 60s timeout
- `spark-worker-surge` — 60s timeout
- `airflow-scheduler-2` — 120s timeout
- `airflow-webserver-2` — 120s timeout

→ Abort + exit 1 if any container times out (permanents untouched)

**5. Verify surge containers are actually serving correctly**

a. `airflow-worker-surge` — confirms connected to Redis and ready to accept tasks:
```bash
docker exec airflow-worker-surge celery \
  --app airflow.providers.celery.executors.celery_executor.app \
  inspect ping -d celery@airflow-worker-surge
```

b. `spark-worker-surge` — worker count must be greater than before surge started (confirms registration with Spark master):
```bash
curl -s http://localhost:8080/json | jq '.workers | length'
```

c. `airflow-scheduler-2` — confirms scheduler is running and writing heartbeats:
```bash
docker exec airflow-scheduler-2 airflow jobs check --job-type SchedulerJob --limit 1
```

d. `airflow-webserver-2` — confirms webserver is up and metadata DB connection is healthy:
```bash
curl -sf http://localhost:8082/health
```

→ Abort + exit 1 if any check fails

**6. Roll airflow-worker**

a. Stop old worker accepting new tasks (airflow-worker-surge picks up all new tasks):
```bash
docker exec airflow-worker celery \
  --app airflow.providers.celery.executors.celery_executor.app \
  control cancel_consumer default
```

b. Poll until no tasks are actively running on old worker (300s timeout, 5s interval — allows long Spark submits to finish):
```bash
docker exec airflow-worker celery \
  --app airflow.providers.celery.executors.celery_executor.app \
  inspect active --timeout 5
```
→ Abort + exit 1 if timeout

c. Stop and remove old worker, bring up permanent on new image:
```bash
docker compose stop airflow-worker && docker compose rm -f airflow-worker
docker compose up -d --no-deps --force-recreate airflow-worker
```

d. Poll Docker healthcheck on `airflow-worker` == `"healthy"` (60s timeout), then confirm connected:
```bash
docker exec airflow-worker celery \
  --app airflow.providers.celery.executors.celery_executor.app \
  inspect ping -d celery@airflow-worker
```

e. Drain `airflow-worker-surge` before removing it — it may have picked up tasks while the old worker was draining:
```bash
docker exec airflow-worker-surge celery \
  --app airflow.providers.celery.executors.celery_executor.app \
  control cancel_consumer default
```

f. Poll until no tasks are actively running on `airflow-worker-surge` (300s timeout, 5s interval):
```bash
docker exec airflow-worker-surge celery \
  --app airflow.providers.celery.executors.celery_executor.app \
  inspect active --timeout 5
```
→ Abort + exit 1 if timeout

g. Remove surge worker:
```bash
docker compose stop airflow-worker-surge && docker compose rm -f airflow-worker-surge
```

**7. Roll spark-worker**

a. Send SIGPWR to stop old worker accepting new tasks (requires `spark.decommission.enabled=true`):
```bash
docker kill --signal SIGPWR spark-worker
```

b. Poll until no active tasks remain on `spark-worker` across all running apps (300s timeout, 5s interval):
```bash
APPS=$(curl -s http://localhost:8080/api/v1/applications | jq -r '.[] | select(.status=="RUNNING") | .id')
# for each APP_ID:
curl -s http://localhost:8080/api/v1/applications/$APP_ID/executors \
  | jq '[.[] | select(.hostPort | startswith("spark-worker:")) | .activeTasks] | add // 0'
# sum across all apps must equal 0
```
→ Abort + exit 1 if timeout

c. Stop and remove old worker, bring up permanent on new image:
```bash
docker compose stop spark-worker && docker compose rm -f spark-worker
docker compose up -d --no-deps --force-recreate spark-worker
```

d. Poll spark-master `/json` until `spark-worker` re-registers (60s timeout):
```bash
curl -s http://localhost:8080/json | jq '.workers[].id'
```

e. Drain `spark-worker-surge` before removing it — it may have picked up tasks while the old worker was draining:
```bash
docker kill --signal SIGPWR spark-worker-surge
```

f. Poll until no active tasks remain on `spark-worker-surge` across all running apps (300s timeout, 5s interval):
```bash
# for each APP_ID:
curl -s http://localhost:8080/api/v1/applications/$APP_ID/executors \
  | jq '[.[] | select(.hostPort | startswith("spark-worker-surge:")) | .activeTasks] | add // 0'
# sum across all apps must equal 0
```
→ Abort + exit 1 if timeout

g. Remove surge worker:
```bash
docker compose stop spark-worker-surge && docker compose rm -f spark-worker-surge
```

**8. Restart spark-master**

Filesystem recovery mode preserves running job state across the restart:
```bash
docker compose up -d --no-deps --force-recreate spark-master
```

**9. Roll airflow-scheduler-1**

a. Recreate on new image:
```bash
docker compose up -d --no-deps --force-recreate airflow-scheduler-1
```

b. Poll until healthy (120s timeout, 5s interval):
```bash
docker exec airflow-scheduler-1 airflow jobs check --job-type SchedulerJob --limit 1
```
→ Abort + exit 1 if timeout

c. Remove surge scheduler:
```bash
docker compose stop airflow-scheduler-2 && docker compose rm -f airflow-scheduler-2
```

**10. Roll airflow-webserver-1**

a. Recreate on new image:
```bash
docker compose up -d --no-deps --force-recreate airflow-webserver-1
```

b. Poll until healthy (120s timeout, 5s interval):
```bash
curl -sf http://localhost:8080/health
```
→ Abort + exit 1 if timeout

c. Remove surge webserver:
```bash
docker compose stop airflow-webserver-2 && docker compose rm -f airflow-webserver-2
```

**11. Exit 0** — only primary instances running

**Rollback (`./deploy.sh --rollback`):**
- Reads SHA from `~/.steam/last_good_sha`
- Re-runs steps 3–10 using pinned `:<sha>` tag instead of `:latest`
- Same health check gates

**Abort behavior:**
- Logs last 50 lines of the failed container
- All un-rolled instances remain on the old image (no action needed)
- Exit 1

### Step 4 — `setup.sh` (modify)

After cloning repos:
1. Copy `.env.example` → `.env` if `.env` does not exist
2. Generate `AIRFLOW_FERNET_KEY` via `python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"`
3. Generate `AIRFLOW_SECRET_KEY` via `openssl rand -hex 32`
4. Write both generated values into `.env` (replace placeholder lines or append)
5. Print reminder that MinIO credentials require manual values

### Step 5 — `.env.example` (modify)

Add to the Airflow section:
```
# Auto-generated by setup.sh — do not set manually
AIRFLOW_FERNET_KEY=
AIRFLOW_SECRET_KEY=
```

### Step 6 — `steam-pipelines/.github/workflows/docker-publish.yml` (modify)

After the `build-and-push` step succeeds, add a step that dispatches a `repository_dispatch` event to `steam-orchestration`:
```yaml
- name: Trigger orchestration build
  if: success()
  uses: peter-evans/repository-dispatch@v3
  with:
    token: ${{ secrets.GH_DISPATCH_TOKEN }}
    repository: Dulain-Willis/steam-orchestration
    event-type: pipelines-updated
```

### Step 7 — `steam-orchestration/.github/workflows/docker-publish.yml` (modify)

Add `repository_dispatch` trigger (in addition to existing `push`/`workflow_dispatch`) and add dispatch step to `steam-data-platform` after successful build:
```yaml
on:
  push:
    branches: [main]
  workflow_dispatch:
  repository_dispatch:
    types: [pipelines-updated]

# after build-and-push step:
- name: Trigger deployment
  if: success()
  uses: peter-evans/repository-dispatch@v3
  with:
    token: ${{ secrets.GH_DISPATCH_TOKEN }}
    repository: Dulain-Willis/steam-data-platform
    event-type: deploy
```

### Step 8 — `steam-data-platform/.github/workflows/deploy.yml` (new file)

```yaml
on:
  repository_dispatch:
    types: [deploy]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to production
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.DEPLOY_HOST }}
          username: ${{ secrets.DEPLOY_USER }}
          key: ${{ secrets.DEPLOY_SSH_KEY }}
          script: |
            cd ~/steam/steam-data-platform
            git pull origin main
            bash deploy.sh
```

---

## Files Modified / Created

| File | Status |
|---|---|
| `steam-data-platform/compose.yml` | MODIFY — switch to CeleryExecutor, add Redis, add airflow-worker, add Traefik, dual instances, surge worker |
| `steam-data-platform/traefik/traefik.yml` | NEW |
| `steam-data-platform/deploy.sh` | NEW |
| `steam-data-platform/setup.sh` | MODIFY — add Fernet/secret key generation |
| `steam-data-platform/.env.example` | MODIFY — add two new variables |
| `steam-data-platform/.github/workflows/deploy.yml` | NEW |
| `steam-orchestration/.github/workflows/docker-publish.yml` | MODIFY — add dispatch trigger + dispatch step |
| `steam-orchestration/` (requirements) | MODIFY — add `apache-airflow-providers-celery` so the worker can run |
| `steam-pipelines/.github/workflows/docker-publish.yml` | MODIFY — add dispatch step |

---

## Verification

1. **Local stack test:** `docker compose up -d` → all services start, Traefik routes `http://localhost` to both webserver instances (verify round-robin by checking access logs or container logs), Airflow UI accessible.
2. **Manual deploy test:** Run `./deploy.sh` on the local machine (pointing `compose.yml` services at localhost). Verify each rolling step completes and health checks pass.
3. **Rollback test:** Intentionally break a health check (invalid image tag), verify script aborts and exits 1, then run `./deploy.sh --rollback` and verify recovery.
4. **CI chain test (Step 10 in DEPLOYMENT_PLAN.md):** Push trivial change to `steam-pipelines/main`, watch GitHub Actions run the full chain: pipelines build → orchestration build → data-platform deploy → health checks pass.
