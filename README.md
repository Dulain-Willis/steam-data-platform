<h1 align="center">Steam Data Platform</h1>

<h3 align="center">A cloud native data platform built like production, not like a demo</h3>

<p align="center">
  <img alt="AWS" src="https://img.shields.io/badge/AWS-232F3E">
  <img alt="Snowflake" src="https://img.shields.io/badge/Snowflake-29B5E8?logo=snowflake&logoColor=white">
  <img alt="dbt" src="https://img.shields.io/badge/dbt-FF694B">
  <img alt="Airflow" src="https://img.shields.io/badge/Airflow-017CEE?logo=apacheairflow&logoColor=white">
  <img alt="Kafka" src="https://img.shields.io/badge/Kafka-231F20?logo=apachekafka&logoColor=white">
  <img alt="PostgreSQL" src="https://img.shields.io/badge/PostgreSQL-4169E1?logo=postgresql&logoColor=white">
</p>

<p align="center">
  <img alt="Terraform" src="https://img.shields.io/badge/Terraform-844FBA?logo=terraform&logoColor=white">
  <img alt="Kubernetes" src="https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white">
  <img alt="Argo CD" src="https://img.shields.io/badge/Argo%20CD-EF7B4D?logo=argo&logoColor=white">
  <img alt="Debezium" src="https://img.shields.io/badge/Debezium-090F1B">
</p>

<div align="center">

[Infra »](https://github.com/Dulain-Willis/steam-infra) | [Analytics »](https://github.com/Dulain-Willis/steam-analytics) | [Orchestration »](https://github.com/Dulain-Willis/steam-orchestration)

</div>
<br>

Most data engineering projects are toy projects. That is fine for learning, fun, and proofs of concept. This one is built to resemble a cloud native production data platform at scale, which means being judged on what production platforms are actually judged on: whether environments are isolated by permissions rather than by convention, whether a bad deploy can reach prod without a human approving it, and whether the pipeline survives the dirty data every real source system produces.

## Diagram

<img width="1452" height="1083" alt="Steam CDC Pipeline Architecture" src="https://github.com/user-attachments/assets/0ecac8c1-a85f-408d-824e-a89e66fee1c8" />

<br>

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

## Repos
An index of the repos that make up this Steam data platform.

| Repo | Description |
| --- | --- |
| [steam-infra](https://github.com/Dulain-Willis/steam-infra) | Infrastructure as Code including Terraform AWS resources and Kubernetes + ArgoCD manifests |
| [steam-analytics](https://github.com/Dulain-Willis/steam-analytics) | dbt Core project transforming `steam-infra`'s Snowflake landing tables into an analytics-ready warehouse |
| [steam-orchestration](https://github.com/Dulain-Willis/steam-orchestration) | Airflow DAGs (via Cosmos) orchestrating the `steam-analytics` dbt project on `steam-infra`'s EKS cluster |
