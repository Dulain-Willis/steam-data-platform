# steam-data-platform

Most data engineering projects are toy projects. That is fine for learning, fun, and proofs of concept. This one is built to resemble a cloud native production data platform at scale, which means being judged on what production platforms are actually judged on: whether environments are isolated by permissions rather than by convention, whether a bad deploy can reach prod without a human approving it, and whether the pipeline survives the dirty data every real source system produces.

## How This Differs From a Toy Project

### 1. The Source

PostgreSQL on AWS RDS, fed by a containerized event generator modelling Steam's real domain: purchases, gifts, key redemptions, refunds and chargebacks, regional pricing, playtime sessions, family sharing, wishlists, reviews, and a client side funnel with realistic drop-off.

### 2. Deliberately Imperfect Data

The generator injects the faults real platforms hit: late-arriving events, backdated corrections, duplicate transactions from retries, unannounced enum values, orphaned events, compliance deletes, and upstream schema migrations. Each is handled the industry standard way and covered by tests plus volume and freshness anomaly detection.

### 3. The Platform

CDC from Postgres to Snowflake via Debezium and Kafka. Everything runs on AWS, provisioned with Terraform and reconciled by ArgoCD on EKS (Kubernetes). Snowflake access is split by workload, so a dev build physically cannot write staging or prod.

### 4. CI/CD Pipeline

Every PR builds into a disposable schema and defers unchanged models to prod's state. Nothing writes prod's image tag automatically; promotion opens a one-line PR, and merging it is the approval and the deploy. Rollback is the same flow, and refuses any tag that has never run.

<br>

## Diagram

<img width="1452" height="1083" alt="Steam CDC Pipeline Architecture" src="https://github.com/user-attachments/assets/0ecac8c1-a85f-408d-824e-a89e66fee1c8" />

<br>
<br>

## Repos
An index of the repos that make up this Steam data platform.

| Repo | Description |
| --- | --- |
| [steam-infra](https://github.com/Dulain-Willis/steam-infra) | Infrastructure as Code including Terraform AWS resources and Kubernetes + ArgoCD manifests |
| [steam-analytics](https://github.com/Dulain-Willis/steam-analytics) | dbt Core project transforming `steam-infra`'s Snowflake landing tables into an analytics-ready warehouse |
| [steam-orchestration](https://github.com/Dulain-Willis/steam-orchestration) | Airflow DAGs (via Cosmos) orchestrating the `steam-analytics` dbt project on `steam-infra`'s EKS cluster |
