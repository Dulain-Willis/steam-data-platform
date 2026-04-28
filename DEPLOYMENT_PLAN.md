# Steam Data Platform — Deployment Plan

## Overview

This document is a complete implementation spec for the production deployment infrastructure of the Steam Data Platform. It is written for an LLM implementor with zero prior context. Read the full document before writing any code.

The Steam Data Platform is a self-hosted, containerized data engineering stack. It ingests Steam game data, processes it through a lakehouse pipeline, and serves analytics via ClickHouse. The platform is spread across five sibling repositories that must live in the same parent directory:

```
steam/
├── steam-data-platform/   ← YOU ARE HERE (glue repo, compose, deployment)
├── steam-orchestration/   ← Airflow + Spark submitter (custom Docker image)
├── steam-pipelines/       ← PySpark jobs + Python package (custom Docker image)
├── steam-infra/           ← Terraform (MinIO buckets) + ClickHouse init SQL
└── steam-analytics/       ← dbt models (no container, runs locally)
```

**What we are building:** A zero-downtime rolling deployment system that automatically deploys new versions of the two custom images (`steam-pipelines` and `steam-orchestration`) to a single production machine when code is merged to `main` on either repo. No paid services. No Kubernetes. Fully reproducible — any user can clone the repos and run the stack locally with a single setup command.

---

## System Architecture

### Container Inventory

There are two categories of containers:

**Custom images (deployment targets):**

| Container(s) | Image | Source repo |
|---|---|---|
| `airflow-webserver-1`, `airflow-webserver-2`, `airflow-scheduler-1`, `airflow-scheduler-2`, `airflow-init` | `ghcr.io/dulain-willis/steam-orchestration` | `steam-orchestration` |
| `spark-master`, `spark-worker` | `ghcr.io/dulain-willis/steam-pipelines` | `steam-pipelines` |

**Third-party images (never redeployed, only version-bumped manually):**

| Container | Image |
|---|---|
| `postgres` | `postgres:16` |
| `minio` | `minio/minio` |
| `clickhouse` | `clickhouse/clickhouse-server` |
| `iceberg-rest` | `tabulario/iceberg-rest:0.9.0` |
| `tabix` | `spoonest/clickhouse-tabix-web-client:stable` |
| `mc` | `minio/mc` |
| `terraform` | `hashicorp/terraform` |

**New container (added by this implementation):**

| Container | Image | Role |
|---|---|---|
| `traefik` | `traefik:v3` | Reverse proxy and load balancer for Airflow webserver instances |

### Critical Build Dependency

`steam-orchestration`'s Dockerfile contains:
```dockerfile
COPY --from=ghcr.io/dulain-willis/steam-pipelines:latest ...
```

This means **`steam-pipelines` must be built and pushed to GHCR before `steam-orchestration` can build**. Any CI/CD pipeline must enforce this order.

### Rolling Architecture

The stateful backing services (Postgres, MinIO, ClickHouse, Iceberg REST) are never restarted as part of deployment — they run continuously. Only the Airflow and Spark containers are rolled.

```
Internet / localhost
        │
    [ Traefik ]  ← round-robin across both webserver instances
        │
   ┌────┴────┐
[airflow-webserver-1]  [airflow-webserver-2]   ← rolled one at a time (restart in place)
[airflow-scheduler-1]  [airflow-scheduler-2]   ← rolled one at a time (restart in place)
[spark-worker]                                 ← rolling with surge (see below)
[spark-master]                                 ← plain restart (brief downtime)
        │
   [ postgres  ]  ← shared, always running
   [ minio     ]
   [ clickhouse]
   [ iceberg   ]
```

Traefik performs round-robin load balancing across both webserver instances at all times. During a rolling restart, one instance is briefly down while the other continues serving traffic. Both instances always have `traefik.enable=true` — no dynamic label toggling needed.

**Spark worker rolling strategy (surge):** There is one permanent worker (`spark-worker`). During deployment a temporary second worker (`spark-worker-surge`) is spun up on the new image, health-checked, and only once it is healthy is the old worker removed. At no point are zero workers running. The temporary worker is removed at the end of the deploy, returning to a single permanent worker. Surge is used here because workers are stateless — two workers running simultaneously on different image versions cannot conflict. It is not used for schedulers or the master because concurrent instances of those services cause duplicate job scheduling or broken cluster registration respectively.

---

## Requirements

- **Zero downtime deployments.** The Airflow webserver must remain reachable throughout every deployment. No planned maintenance windows. (Exception: Spark master restarts cause brief downtime — seconds, not minutes — which is acceptable since it is not user-facing.)
- **Rolling strategy.** Services with multiple instances are restarted one at a time. At least one healthy instance remains available at all times during the rollout. No mixed-version window for Airflow's metadata DB is introduced by this strategy since schedulers and webservers are restarted sequentially, not simultaneously.
- **Automated deployment on push to `main`.** Merging to `main` on either `steam-pipelines` or `steam-orchestration` triggers a full build + deploy without manual intervention.
- **Automated rollback on health check failure.** If any instance fails its health check during the rolling restart, the deploy script must abort, leave all remaining instances on the old image, and exit non-zero so GitHub Actions marks the run as failed.
- **Fully open source, zero cost.** No paid SaaS, no managed cloud services. All tooling must be self-hostable.
- **Single machine target.** All containers run on one Linux host. No cluster orchestration needed.
- **Reproducible for new users.** Any contributor must be able to clone all repos, run `./setup.sh`, and have the full stack running locally with `docker compose up`. The deployment system must not break local development workflows.
- **Secrets via `.env` file.** Secrets are stored in a `.env` file on the server (gitignored). A `.env.example` documents every required variable. A setup script auto-generates secrets where possible (e.g. Airflow Fernet key).
- **Image registry is GHCR.** Both custom images are already published to GitHub Container Registry (`ghcr.io/dulain-willis/`). This must remain the registry.

---

## Non-Requirements

These are explicitly out of scope. Do not implement them.

- **No Kubernetes.** Not even k3s. Docker Compose is the correct tool for a single machine. K8s adds control-plane overhead with no benefit here.
- **No GitOps tools (ArgoCD, Flux).** These are Kubernetes-native. GitHub Actions + a deploy script is sufficient.
- **No secrets manager (Vault, Doppler, etc.).** `.env` files on the server are the correct approach for a self-hosted single-machine project. Vault is for multi-service, multi-team secret distribution.
- **No container image scanning or SBOM generation.** Out of scope for this implementation.
- **No multi-environment promotion (dev → staging → prod).** There is one environment. It is production.
- **No blue/green deployments.** Rolling is the strategy. Duplicate full environment sets add complexity with no benefit at this scale.
- **No canary deployments or weighted traffic splitting.** Traefik performs simple round-robin. Traffic is not weighted by version.
- **No horizontal scaling beyond two instances.** Two webservers, two schedulers, two Spark workers. Scale-out is a future concern.
- **No database migrations as part of deployment.** Airflow runs `airflow db migrate` on startup. ClickHouse schema is managed by init scripts in `steam-infra` and only runs on first start. No migration tooling needed in the deploy pipeline.
- **No monitoring or alerting system.** Health checks are for deployment gating only, not ongoing observability.
- **No Docker registry mirror or caching proxy.** Pull directly from GHCR and Docker Hub.

---

## Tooling

| Tool | Version | Role | Why |
|---|---|---|---|
| Docker Compose | v2 (plugin) | Container orchestration on single machine | Native, no overhead |
| Traefik | v3 | Round-robin load balancer for Airflow webserver | Docker-native label routing, automatic service discovery, free |
| GitHub Actions | — | CI: build images + trigger deploy | Already in use |
| Bash | — | Deploy script on production machine | No dependencies, auditable |
| GHCR | — | Image registry | Already in use, free with GitHub |

---

## Repository Structure After Implementation

Files to be created or modified are marked with `[NEW]` or `[MODIFY]`.

```
steam-data-platform/
├── compose.yml              [MODIFY] add Traefik; define two instances each of webserver, scheduler, worker
├── .env.example             [MODIFY] add DEPLOY_HOST, any new vars
├── setup.sh                 [MODIFY] add Fernet key generation
├── deploy.sh                [NEW] rolling deploy script (runs on production machine)
├── traefik/
│   └── traefik.yml          [NEW] static Traefik config (round-robin, no dynamic config)
└── .github/
    └── workflows/
        └── deploy.yml       [NEW] GHA workflow: SSH into machine, run deploy.sh

steam-orchestration/
└── .github/workflows/
    └── docker-publish.yml   [MODIFY] on success, trigger steam-data-platform deploy workflow

steam-pipelines/
└── .github/workflows/
    └── docker-publish.yml   [NEW] mirror of orchestration's publish workflow
```

---

## Build Pipeline

### Trigger Chain

```
Push to steam-pipelines/main
  → Build & push ghcr.io/.../steam-pipelines:latest + :<sha>
  → On success: repository_dispatch to steam-orchestration

Push to steam-orchestration/main  (or triggered by pipelines dispatch)
  → Build & push ghcr.io/.../steam-orchestration:latest + :<sha>
  → On success: repository_dispatch to steam-data-platform

steam-data-platform receives dispatch
  → SSH into production machine
  → Run deploy.sh
```

### Image Tagging

Every push produces two tags:
- `latest` — always points to the most recent build on `main`
- `<git-sha>` (short, 7 chars) — immutable, used for rollback

The deploy script records the SHA of the currently running image before replacing it so rollback has a specific tag to revert to, not just `latest`.

### GitHub Actions Secrets Required

These secrets must be set on the `steam-data-platform` repository (and `steam-orchestration` for the dispatch token):

| Secret | Description |
|---|---|
| `DEPLOY_SSH_KEY` | Private SSH key for the production machine |
| `DEPLOY_HOST` | Hostname or IP of the production machine |
| `DEPLOY_USER` | SSH username on the production machine |
| `GH_DISPATCH_TOKEN` | GitHub PAT with `repo` scope, for cross-repo `repository_dispatch` |

---

## Deploy Script Logic (`deploy.sh`)

The deploy script runs **on the production machine** over SSH. It must be idempotent.

```
1. Pull new images:
   docker pull ghcr.io/dulain-willis/steam-orchestration:latest
   docker pull ghcr.io/dulain-willis/steam-pipelines:latest

2. Record current image SHAs to ~/.steam/last_good_sha (for rollback)

3. Roll Spark worker (surge strategy):
   a. docker compose up -d --no-deps spark-worker-surge  (new image, defined in compose.yml)
   b. Wait for health check: spark-worker-surge appears in spark-master's worker list
      (poll `docker exec spark-master curl -s http://localhost:8081/json` for worker count)
   c. If health check fails within timeout: remove spark-worker-surge, abort, exit 1
   d. docker compose stop spark-worker && docker compose rm -f spark-worker
   e. Rename/relabel: spark-worker-surge becomes the permanent worker going forward
      (or simply leave spark-worker-surge running — compose treats it as the active worker)

4. Restart Spark master (plain restart — brief downtime accepted):
   docker compose up -d --no-deps --force-recreate spark-master

5. Roll Airflow schedulers one at a time (scheduler-1, then scheduler-2):
   a. docker compose up -d --no-deps --force-recreate airflow-scheduler-N
   b. Wait for health check:
      docker exec airflow-scheduler-N airflow jobs check --job-type SchedulerJob --limit 1
   c. If health check fails within timeout: abort, exit 1

6. Roll Airflow webservers one at a time (webserver-1, then webserver-2):
   a. docker compose up -d --no-deps --force-recreate airflow-webserver-N
   b. Wait for health check: HTTP GET http://localhost:{port}/health → 200
      Traefik continues routing traffic to the instance that is still up
   c. If health check fails within timeout: abort, exit 1

7. Exit 0
```

**On abort (any health check timeout):**
- Log failure with a snippet of the failed container's logs
- All instances not yet rolled remain on the old image and continue serving
- Exit 1 (GHA marks deploy as failed)

### Port Allocation

Each instance binds a distinct host port. Traefik handles external routing on port 80 (or 8080).

| Service | Instance 1 port | Instance 2 port | Traefik external port |
|---|---|---|---|
| airflow-webserver | 8080 | 8082 | 80 (or 8080) |
| spark-master UI | 8081 | — | — (not proxied) |

---

## Health Checks

### Airflow webserver (per instance)
`GET /health` on the instance's host port returns HTTP 200. This endpoint is built into Airflow and confirms the webserver process is alive and connected to the metadata DB.

### Airflow scheduler (per instance)
`airflow jobs check --job-type SchedulerJob --limit 1` exits 0 inside the container. This confirms the scheduler has registered a heartbeat with the metadata DB — not just that the process started.

### Spark worker (per instance)
The worker appears in the Spark master's worker list: `curl http://localhost:8081/json` returns a `workers` array containing the new worker. Timeout: 60 seconds.

### Spark master
No health gate. The deploy script restarts it and immediately moves on. If it fails to start, Spark jobs will fail visibly, which is acceptable.

---

## Rollback

**Automatic rollback** occurs when any health check in the rolling deploy times out. The deploy script aborts and all un-rolled instances keep running on the old image. No explicit action needed — the partially-rolled set continues serving.

**Manual rollback** (if a bad deploy slipped through health checks):
```bash
# On the production machine:
./deploy.sh --rollback
```
The `--rollback` flag makes the script:
1. Read the previous image SHA from `~/.steam/last_good_sha`
2. Re-run the same rolling sequence but with the pinned SHA instead of `latest`
3. Run health checks at each step
4. Exit 0 on success, 1 on failure

---

## Traefik Configuration

Traefik runs as a permanent service in `compose.yml`. It listens on port 80 (or 8080) and load balances across both Airflow webserver instances using round-robin.

Static config (`traefik/traefik.yml`):
- Provider: Docker (reads labels from containers on the same Docker network)
- No TLS required (single machine, not internet-facing)
- Dashboard enabled on port 8090 for debugging

Both `airflow-webserver-1` and `airflow-webserver-2` carry `traefik.enable=true` at all times. No label toggling is needed — Traefik's Docker provider automatically removes a container from rotation when it goes unhealthy or stops, and re-adds it when it comes back up. This is what provides zero-downtime during the rolling restart.

---

## Rolling Deployment Safety Rules

Rolling deployment is safe as long as these rules are followed. Violating them during a deploy can cause data corruption, duplicate writes, or broken DAG runs.

### 1. Backward-Compatible Changes Only

Never remove or rename a database column, table, or task output in a single deploy. The mixed-version window means the old code and new code run simultaneously against the same data stores.

The safe sequence:
1. Add the new field/table (both versions can coexist)
2. Deploy code that writes to the new field and reads from both
3. Deploy code that reads only from the new field
4. Remove the old field in a later deploy

### 2. Idempotent Tasks

Every Spark job and Airflow task must be safe to run twice with the same inputs and produce the same result. Use upserts/MERGE instead of INSERT, use deterministic output paths, avoid side effects that compound on retry.

This also covers automatic recovery: when the Airflow scheduler restarts during a deploy, any task that was actively running loses its heartbeat. The new scheduler marks it as a zombie and retries it after ~5 minutes. If tasks are idempotent, the retry is harmless. If they are not, it will cause duplicate data.

### 3. Drain Spark Workers Before Terminating

Stop workers from accepting new tasks, let any in-flight tasks finish, then terminate. This avoids killing work mid-execution and forcing a retry.

### 4. Keep Deploy Windows Short

The mixed-version window (period where instance 1 is on the new image and instance 2 is still on the old) is a risk surface. Faster health checks and faster container startup = smaller window. Avoid adding slow initialization logic to the images that delays the rollout.

### 5. Avoid Breaking DAG Changes

Do not change task IDs, task dependencies, or XCom key names in a way that would break a DAG run that is currently in progress. A running DAG run was scheduled against the old DAG definition — changing its structure mid-run causes inconsistent state in the metadata DB.

If a breaking DAG change is necessary, version the DAG instead of modifying it in place (e.g. `steam_ingest_v2`) and retire the old one after all its active runs complete.

### 6. Handle Schema Changes in Phases (Expand-Contract)

This is a formal pattern called expand-contract. Any schema change that could break the old version of the code must be split across multiple deploys:

- **Phase 1 (expand):** Add the new schema alongside the old. Both versions of the code can run against it.
- **Phase 2 (contract):** Deploy code that uses only the new schema.
- **Phase 3 (cleanup):** Remove the old schema in a subsequent deploy once no running instance references it.

Never combine phases 1 and 2 into a single deploy.

---

## Secrets and Local Setup

### For production (`~/.steam/.env` on the server)

The `.env` file is **never committed**. It is generated by `setup.sh` and lives on the machine. The deploy script sources it before running compose commands.

### For local development

Same flow: clone repos, run `setup.sh`, get a generated `.env`. The `.env.example` documents every variable.

### `setup.sh` responsibilities (after modification)

1. Clone all sibling repos (already implemented)
2. Copy `.env.example` to `.env` if `.env` does not exist
3. Generate `AIRFLOW_FERNET_KEY` using Python: `from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())`
4. Write generated values into `.env`
5. Print next steps

### Variables requiring user action (cannot be auto-generated)

```
MINIO_ACCESS_KEY        — choose any string
MINIO_SECRET_KEY        — choose any string (min 8 chars)
MINIO_ROOT_USER         — choose any string
MINIO_ROOT_PASSWORD     — choose any string
```

All other variables in `.env.example` either have safe defaults or are auto-generated.

---

## What Does NOT Change

The following must remain exactly as they are. Do not modify them:

- The `steam-orchestration` Dockerfile — it correctly pulls from `steam-pipelines:latest` at build time
- The `steam-pipelines` Dockerfile — no changes needed
- The backing service configurations (Postgres, MinIO, ClickHouse, Iceberg REST) in `compose.yml`
- The volume mounts for DAGs, plugins, and Spark jobs (these are bind mounts from sibling repos, not part of the image)
- GHCR as the image registry

---

## Implementation Checklist

Work in this order. Each step should be independently testable before moving to the next.

- [ ] 1. Add Traefik service to `compose.yml` and create `traefik/traefik.yml`
- [ ] 2. Add two named instances each of `airflow-webserver` and `airflow-scheduler` to `compose.yml` with Traefik labels on the webserver instances; add `spark-worker-surge` as a second service definition (normally stopped, started only during deploy)
- [ ] 3. Test locally: `docker compose up` starts correctly and Traefik round-robins across both webserver instances
- [ ] 4. Write `deploy.sh` with full rolling logic, per-instance health checks, and `--rollback` flag
- [ ] 5. Update `setup.sh` to generate Fernet key
- [ ] 6. Update `.env.example` with any new variables
- [ ] 7. Add `docker-publish.yml` workflow to `steam-pipelines` (mirror `steam-orchestration`'s existing workflow)
- [ ] 8. Modify `steam-orchestration/docker-publish.yml` to send `repository_dispatch` to `steam-data-platform` on successful push
- [ ] 9. Create `steam-data-platform/.github/workflows/deploy.yml` — receives dispatch, SSHes into machine, runs `deploy.sh`
- [ ] 10. End-to-end test: push a trivial change to `steam-pipelines`, verify full chain completes and Airflow is reachable throughout
