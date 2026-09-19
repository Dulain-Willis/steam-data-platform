# steam-data-platform

<br>

<img width="3166" height="1852" alt="image" src="https://github.com/user-attachments/assets/28e47205-0a96-4357-8245-38b2f47e0c75" />

<br>
<br>

An index of the repos that make up this Steam data platform.

| Repo | Description |
| --- | --- |
| [steam-infra](https://github.com/Dulain-Willis/steam-infra) | Terraform-provisioned cloud infrastructure (AWS EKS, Snowflake) plus a synthetic Steam data generator |
| [steam-analytics](https://github.com/Dulain-Willis/steam-analytics) | dbt Core project transforming `steam-infra`'s Snowflake landing tables into an analytics-ready warehouse |
| [steam-orchestration](https://github.com/Dulain-Willis/steam-orchestration) | Airflow DAGs (via Cosmos) orchestrating the `steam-analytics` dbt project on `steam-infra`'s EKS cluster |
