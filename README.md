# steam-data-platform
Many data engineering/analytics projects are "toy projects". This is perfectly fine for learning, fun, POC's. However, this project is meant to resemble a real Cloud Native Production Data Platform at scale as close as possible. Although an impossible task unless it's truly a real maintained project within a firm I did my best in various ways. 


- **The Source:** PostgreSQL instance on AWS RDS with thousands of user operations per second. 

- **The Platform:** Cloud native, everything runs on AWS, provisioned with Terraform.

- **CI/CD Pipeline:** Every PR runs CI checks, and every merge triggers rolling deployments on Kubernetes pods through ArgoCD

<br>

## Diagram

<img width="1452" height="1083" alt="Steam CDC Pipeline Architecture" src="https://github.com/user-attachments/assets/0ecac8c1-a85f-408d-824e-a89e66fee1c8" />

<br>
<br>

## Repos
An index of the repos that make up this Steam data platform.

| Repo | Description |
| --- | --- |
| [steam-infra](https://github.com/Dulain-Willis/steam-infra) | Infrastructure as Code including Terraform AWS resources and Kuberenetes + ArgoCD manifests |
| [steam-analytics](https://github.com/Dulain-Willis/steam-analytics) | dbt Core project transforming `steam-infra`'s Snowflake landing tables into an analytics-ready warehouse |
| [steam-orchestration](https://github.com/Dulain-Willis/steam-orchestration) | Airflow DAGs (via Cosmos) orchestrating the `steam-analytics` dbt project on `steam-infra`'s EKS cluster |
