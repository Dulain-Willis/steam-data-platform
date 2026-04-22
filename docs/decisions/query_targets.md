# Makefile Query Targets

The problem was simple: querying Parquet files in MinIO with DuckDB required typing out S3 credentials and httpfs setup on every session, and spinning up `spark-sql` to query Iceberg tables meant passing a wall of `--conf` flags each time. Neither is something you want to do manually when you're just trying to inspect some data quickly.

The obvious fix — put the credentials in `~/.duckdbrc` or a shell alias — would have worked, but it ties the setup to a specific machine rather than the project. Anyone cloning the repo would have to figure out the incantation themselves. `direnv` was another option that keeps things project-local, but it requires a system-level install and shell hook setup, which felt like too much for what is essentially a developer convenience.

A Makefile target ended up being the right call. Make is already part of the project, there's no new tooling to install, and the targets live in the repo so they travel with it. The `duck` target loads `infra/minio/minio.sql` on startup, which handles the httpfs install and S3 credential config so the shell comes up ready to query. For one-off queries you can pass `q=` directly and get output without entering an interactive shell — useful for piping into other tools or just grabbing a quick count.

```bash
make duck q="SELECT COUNT(*) FROM read_parquet('s3://warehouse/steamspy/silver/data/**/*.parquet')"
```

The `spark` target solves a different problem. DuckDB can read raw Parquet, but it has no concept of Iceberg — it can't see snapshot history, partition metadata, or time travel. For that you need `spark-sql` talking to the Iceberg REST catalog. The `SPARK_CONF` block in the Makefile wires the REST catalog URI, the S3A filesystem settings for MinIO, and sets `iceberg` as the default catalog so you can write `steamspy.games` instead of `iceberg.steamspy.games`. Spark also emits a lot of WARN/INFO noise to stderr, so the target pipes that to `/dev/null` and reformats the tab-separated output to something readable.

```bash
make spark q="SELECT * FROM steamspy.games.snapshots"
```

The tradeoff is that `make spark` requires the `spark-master` container to be running and takes a JVM startup penalty. For anything that's just a quick look at the underlying files, `make duck` is faster. For anything that actually needs Iceberg semantics — time travel, snapshot inspection, checking what changed between runs — `make spark` is the right tool.
