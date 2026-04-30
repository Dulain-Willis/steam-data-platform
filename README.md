# Steam Data Platform

An end-to-end data platform that ingests Steam data, processes it through a multi-layer warehouse, and surfaces analytics-ready models. Fully containerized with Docker Compose and orchestrated by Airflow.

## Architecture

<img width="1280" height="720" alt="Steam Platfomr pciture" src="https://github.com/user-attachments/assets/5890e07a-5791-43d9-a389-63f56a4ec2a7" />

## Repos

| Repo | Description |
|------|-------------|
| [steam-infra](https://github.com/Dulain-Willis/steam-infra) | Terraform (MinIO buckets), ClickHouse init SQL, MinIO DuckDB config |
| [steam-pipelines](https://github.com/Dulain-Willis/steam-pipelines) | PySpark jobs + shared `pipelines` Python library |
| [steam-orchestration](https://github.com/Dulain-Willis/steam-orchestration) | Airflow DAGs and plugins |
| [steam-analytics](https://github.com/Dulain-Willis/steam-analytics) | dbt models (staging → intermediate → marts → metrics) + notebooks |

## Local Dev Quickstart

```bash
# 1. Clone this repo, then clone all sibling repos
git clone https://github.com/Dulain-Willis/steam-data-platform.git
cd steam-data-platform
./setup.sh

# 2. Copy env and configure
cp .env.example .env

# 3. Bring the stack up
docker compose up -d

# 4. Provision MinIO buckets (first time only)
docker compose run --rm terraform init
docker compose run --rm terraform apply -auto-approve

# 5. Trigger pipeline via Airflow UI
# http://localhost:8080  (admin / admin)
```

## Service URLs

| Service | URL |
|---------|-----|
| Airflow | http://localhost:8080 |
| Spark UI | http://localhost:8081 |
| MinIO Console | http://localhost:9001 |
| ClickHouse HTTP | http://localhost:8123 |
| Tabix (CH UI) | http://localhost:8888 |

## Architecture Decisions

All ADRs are centralised in [`docs/decisions/`](docs/decisions/). See also [`docs/contributing.md`](docs/contributing.md) for commit conventions.
