# Service Links

| Service | URL | Credentials |
|---|---|---|
| Airflow | http://localhost:8080 | admin / admin |
| MinIO Console | http://localhost:9001 | minioadmin / minioadmin |
| Tabix (ClickHouse UI) | http://localhost:8888 | clickhouse / clickhouse |
| Spark Master UI | http://localhost:8081 | — |
| ClickHouse HTTP | http://localhost:8123 | clickhouse / clickhouse |
| Iceberg REST Catalog | http://localhost:8181 | — |

## Ports Reference

| Service | Port | Protocol |
|---|---|---|
| Airflow Webserver | 8080 | HTTP |
| Spark Master Web UI | 8081 | HTTP |
| MinIO API | 9000 | S3-compatible HTTP |
| MinIO Console | 9001 | HTTP |
| Tabix | 8888 | HTTP |
| ClickHouse HTTP | 8123 | HTTP |
| ClickHouse Native TCP | 9100 | TCP |
| Iceberg REST | 8181 | HTTP |
| Spark Master | 7077 | TCP |
| Postgres | 5432 | TCP |
