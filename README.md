# steam-data-platform
This project is meant to combat the slew of toy projects surrounding data engineering/analytics. Although an impossible task unless it's truly a real maintained project within a firm I did my best in various ways. 

<br> 

**First - The Source:** PostgreSQL instance on AWS RDS with thousands of user operations per second. 

**Second - The Platform:** Cloud native, everything runs on AWS, provisioned with Terraform.

**Third - CI/CD Pipeline:** Every PR runs CI checks, and every merge triggers rolling deployments on Kubernetes pods through ArgoCD
<br>

<img width="1639" height="960" alt="image" src="https://github.com/user-attachments/assets/73ea4e8f-d81e-41b2-bc96-d9242076dee1" />

<br>
<br>

An index of the repos that make up this Steam data platform.

| Repo | Description |
| --- | --- |
| [steam-infra](https://github.com/Dulain-Willis/steam-infra) | Infrastructure as Code including Terraform AWS resources and Kuberenetes + ArgoCD manifests |
| [steam-analytics](https://github.com/Dulain-Willis/steam-analytics) | dbt Core project transforming `steam-infra`'s Snowflake landing tables into an analytics-ready warehouse |
| [steam-orchestration](https://github.com/Dulain-Willis/steam-orchestration) | Airflow DAGs (via Cosmos) orchestrating the `steam-analytics` dbt project on `steam-infra`'s EKS cluster |
