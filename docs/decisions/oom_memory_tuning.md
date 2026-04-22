
## Overview
The full pipeline stack (Airflow, Spark standalone, MinIO, ClickHouse, Iceberg REST, Postgres) runs inside Docker Desktop on a MacBook with a 3.827 GiB Docker memory allocation. When the steamspy bronze Spark job runs it gets killed with exit code -9, which is SIGKILL — the Linux OOM killer forcibly terminates the process because the system runs out of memory.

This document explains why that happens, what each configuration change fixes, and the constraints that shaped those decisions.

---

## Why exit code -9 means OOM

On Linux, when the kernel runs out of physical memory it invokes the OOM (Out of Memory) killer. The OOM killer picks the most expensive process and sends it SIGKILL (signal 9). Signal 9 cannot be caught or handled — the process is gone instantly. Spark has no chance to write a Java exception or log an error; it just disappears. Airflow sees the spark-submit child process exit with code -9 and raises `AirflowException: Cannot execute ... Error code is: -9`.

This is distinct from a Java heap OOM, which is a controlled JVM error (`java.lang.OutOfMemoryError`) that produces a stack trace and lets Spark log the failure. Exit code -9 means the OS killed it before Java could react.

---

## The memory arithmetic

At idle, before any DAG runs, the stack consumes approximately:

| Container | Idle usage |
|---|---|
| airflow-webserver (4 Gunicorn workers) | ~1.2 GiB |
| airflow-scheduler | ~390 MiB |
| spark-master (JVM daemon) | ~111 MiB |
| spark-worker (JVM daemon) | ~146 MiB |
| minio | ~176 MiB |
| iceberg-rest | ~86 MiB |
| postgres | ~66 MiB |
| tabix | ~6 MiB |
| **Total idle** | **~2.15 GiB** |
| **Docker limit** | **3.827 GiB** |
| **Free for Spark jobs** | **~1.67 GiB** |

The bronze Spark job was configured with:

```
spark.driver.memory=1g
spark.executor.memory=1g
spark.driver.memoryOverhead=384m
spark.executor.memoryOverhead=384m
```

That is 1g + 384m + 1g + 384m = **~2.75 GiB** needed for Spark alone, on top of the 2.15 GiB already in use. Total demand: ~4.9 GiB. Available: 3.827 GiB. The deficit is ~1.1 GiB — the OOM killer fires every time.

---

## What Spark memory settings actually control

### `spark.driver.memory` and `spark.executor.memory`

These are JVM heap sizes. The JVM allocates this memory upfront when it starts, regardless of how much data the job actually processes. Spark then divides the heap into two internal pools:

- **Execution memory** — used for shuffle buffers, sort operations, joins, aggregations. When this fills up, Spark spills intermediate data to disk rather than crashing (for operations that support spilling).
- **Storage memory** — used for caching DataFrames/RDDs explicitly via `.cache()`. Unused in this pipeline.

The two pools share the heap and borrow from each other dynamically via unified memory management.

### `spark.driver.memoryOverhead` and `spark.executor.memoryOverhead`

Memory outside the JVM heap, used by the JVM itself: native libraries, thread stacks, JVM metadata, off-heap Netty buffers. Spark reserves this so that the total JVM process size (heap + overhead) stays within a predictable bound and the OS does not kill the process for exceeding a container memory limit.

The Spark default for overhead is `max(384m, 10% of executor memory)`. At 512m executor memory, 10% is 51m, but 256m is used here as a safer floor — the JVM consistently uses more off-heap memory than the 10% default implies in practice.

### Does Spark honour these limits?

Mostly yes. For operations that support spilling (sorts, hash aggregations, shuffle writes), Spark will write intermediate data to local disk when execution memory fills up. This makes the job slower but not broken. For operations that cannot spill (certain broadcast joins, collect() calls that pull data into the driver), exceeding the heap causes a Java OOM — a controlled failure with a stack trace, not a SIGKILL.

For this pipeline — which reads Parquet from MinIO, applies light transforms, and writes to ClickHouse — 512m is sufficient. The data is tens of MBs; the heap is never under pressure. Spilling does not occur.

---

## Change 1: Reduce Spark memory settings

**File:** `src/pipelines/common/spark/config.py` → `get_spark_resource_conf()`

| Setting | Before | After |
|---|---|---|
| `spark.driver.memory` | 1g | 512m |
| `spark.executor.memory` | 1g | 512m |
| `spark.driver.memoryOverhead` | 384m | 256m |
| `spark.executor.memoryOverhead` | 384m | 256m |
| `spark.sql.shuffle.partitions` | 8 | 4 |
| **Total Spark footprint** | **~2.75 GiB** | **~1.5 GiB** |

`spark.sql.shuffle.partitions` controls how many output partitions Spark creates after a shuffle (e.g. a join or groupBy). The default is 200, which is designed for large clusters. 8 was already a reduction. 4 is appropriate for a single-worker local cluster processing small data — fewer partitions means fewer sort spill buffers and less scheduling overhead.

---

## Change 2: Reduce Airflow webserver workers

**File:** `compose.yml` → `AIRFLOW__WEBSERVER__WORKERS: "1"`

The Airflow webserver runs under Gunicorn, which is a multi-process HTTP server. It forks N worker processes at startup and keeps them alive permanently, each holding the full Airflow Python application in memory (~150–300 MiB per worker).

The default is 4 workers. For a team accessing the UI concurrently, multiple workers prevent request queuing when one is busy. For a single developer, 1 worker is indistinguishable — requests are never concurrent.

| Setting | Before | After | Memory saved |
|---|---|---|---|
| Gunicorn workers | 4 | 1 | ~450–900 MiB |

This has zero effect on DAG scheduling, task execution, or pipeline behaviour. The scheduler is a separate process; the webserver is purely the UI.

---

## Change 3: Serialize replication tasks

**File:** `airflow/dags/replication.py`

The replication DAG iterates over three tables and creates a `SparkSubmitOperator` for each. Without explicit dependencies, Airflow treats sibling tasks as independent and can schedule them concurrently (subject to `max_active_tasks` on the DAG and pool limits).

Each `SparkSubmitOperator` launches a full spark-submit process — a driver JVM plus an executor JVM on the worker. Two concurrent replication tasks mean two driver JVMs and two executor JVMs running simultaneously:

```
2 × (512m driver + 256m overhead + 512m executor + 256m overhead) = ~3.1 GiB for Spark alone
```

That is still too much given the idle overhead of 2.15 GiB. Tasks must run one at a time.

Two mechanisms enforce this:

1. **`max_active_tasks=1` on the DAG** — Airflow will not schedule a second task from this DAG while one is already running, regardless of available worker slots.

2. **Explicit `>>` chaining between tasks** — The tasks have a defined order: `stg_games >> int_developers >> int_publishers`. Even if `max_active_tasks` were removed, the chain prevents the next task from being queued until the previous one completes. The chain also makes the execution order deterministic and visible in the Airflow graph view.

`max_active_tasks=1` alone is sufficient for the memory constraint. The chain is added for clarity and resilience — if the DAG is ever moved to a pool or the limit is relaxed, the serial order is still enforced.

---

## Memory budget after changes

| Item | Memory |
|---|---|
| Stack at idle (with 1 webserver worker) | ~1.3–1.5 GiB |
| Single Spark job (driver + executor + overheads) | ~1.5 GiB |
| **Total peak** | **~2.8–3.0 GiB** |
| Docker limit | 3.827 GiB |
| **Headroom** | **~0.8–1.0 GiB** |

The swap was also increased from 1 GiB to 2 GiB in Docker Desktop settings. Swap on macOS uses compressed memory backed by disk. It will not make jobs faster if triggered, but it prevents SIGKILL during brief spikes that exceed physical allocation — for example, during JVM startup before the GC has had a chance to release unreachable objects.

---

## What was not changed

**Spark standalone mode** was kept. Running Spark in `local[*]` mode (a single JVM for driver and executor) would save the most memory (~600–800 MiB) but removes the standalone cluster components (master, worker, Spark UI). This project intentionally represents a production-style distributed Spark setup even on small data, so standalone mode is preserved.

**ClickHouse** was not tuned. Its mark cache and uncompressed cache are lazy — they allocate memory only when data is actually read and cached. With the SteamSpy dataset (tens of MBs, infrequent reads), both caches remain at 0 bytes in practice. The `max_server_memory_usage_to_ram_ratio = 0.9` setting is aggressive in theory (90% of Docker RAM) but irrelevant given the actual working set. If the dataset grows significantly, adding `infra/clickhouse/init/low_memory.xml` with a lower ratio would be the correct next step.
