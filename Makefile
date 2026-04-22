# duck: Query MinIO Parquet files via DuckDB without manually entering credentials.
#       Loads infra/minio/minio.sql on startup to configure the S3 connection.
#       See docs/minio/querying.md for usage and examples.
MINIO_INIT := ../steam-infra/minio/minio.sql

.PHONY: duck spark clickhouse

ifdef q
duck:
	duckdb -init $(MINIO_INIT) -c "$(q)"
else
duck:
	duckdb -init $(MINIO_INIT)
endif

# spark: Query Iceberg tables via spark-sql inside the running spark-master container.
#        Wires the Iceberg REST catalog and S3A/MinIO credentials via --conf flags.
#        Sets iceberg as the default catalog so table names don't need the iceberg. prefix.
#        See docs/minio/querying.md for usage and examples.
SPARK_CONF := \
  --conf spark.sql.defaultCatalog=iceberg \
  --conf spark.sql.cli.print.header=true \
  --conf spark.sql.catalog.iceberg=org.apache.iceberg.spark.SparkCatalog \
  --conf spark.sql.catalog.iceberg.type=rest \
  --conf spark.sql.catalog.iceberg.uri=http://iceberg-rest:8181 \
  --conf spark.sql.catalog.iceberg.warehouse=s3a://warehouse/ \
  --conf spark.sql.catalog.iceberg.io-impl=org.apache.iceberg.aws.s3.S3FileIO \
  --conf spark.sql.catalog.iceberg.s3.endpoint=http://minio:9000 \
  --conf spark.sql.catalog.iceberg.s3.access-key-id=minioadmin \
  --conf spark.sql.catalog.iceberg.s3.secret-access-key=minioadmin \
  --conf spark.sql.catalog.iceberg.s3.path-style-access=true \
  --conf spark.sql.catalog.iceberg.s3.region=us-east-1 \
  --conf spark.hadoop.fs.s3a.endpoint=http://minio:9000 \
  --conf spark.hadoop.fs.s3a.access.key=minioadmin \
  --conf spark.hadoop.fs.s3a.secret.key=minioadmin \
  --conf spark.hadoop.fs.s3a.impl=org.apache.hadoop.fs.s3a.S3AFileSystem \
  --conf spark.hadoop.fs.s3a.path.style.access=true

ifdef q
# @ suppresses make from echoing the full docker command before running it.
# 2>/dev/null drops WARN/INFO log lines which spark-sql emits on stderr, leaving only query results.
# sed converts tab-separated columns to ' | ' for readability.
spark:
	@docker compose exec spark-master /opt/spark/bin/spark-sql $(SPARK_CONF) -e "$(q)" 2>&1 | sed 's/\t/ | /g'
else
spark:
	@docker compose exec spark-master /opt/spark/bin/spark-sql $(SPARK_CONF)
endif

# clickhouse: Query ClickHouse via clickhouse-client inside the running container.
#             Uses FORMAT Pretty for readable output.
#             See docs/minio/querying.md for usage and examples.
CLICKHOUSE_CMD := docker compose exec clickhouse clickhouse-client --user clickhouse --password clickhouse

ifdef q
clickhouse:
	@$(CLICKHOUSE_CMD) -q "$(q)" --format Pretty
else
clickhouse:
	@$(CLICKHOUSE_CMD)
endif
