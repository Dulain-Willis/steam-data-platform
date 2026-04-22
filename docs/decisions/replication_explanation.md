## Overview

Minio stores iceberg bronze and silver tables transformed using pypark. The analytics layer is hosted in clickhouse with dbt. The silver tables need to be replicated into clickhouse for anlytics use cases. I use iceberg snapshots to be able to tell what has changed since the last replication and what needs ot be updated rather than a traditional watermark.

---

## How Iceberg Snapshots Work

An iceberg snapshot represent the full table state at a given point in time. The flow is Snapshot → Manifest List → Manifest Files → Data Files (with partition info). 

Every snapshot is attatched to a manifest_list


| snapshot_id      | manifest_list                                                        |
| ---------------- | -------------------------------------------------------------------- |
| 8472619384710234 | s3://lakehouse/steamspy/silver/metadata/snap-8472619384710234-1.avro |


  


That manifest list points to manifest files                                                                         


| manifest_path                                            |
| -------------------------------------------------------- |
| s3a://warehouse/steamspy/silver/metadata/manifest-A.avro |
| s3a://warehouse/steamspy/silver/metadata/manifest-B.avro |


  


Each manifest file points to data files                                                                    

manifest-A.avro:


| file_path                                                             | partition    |
| --------------------------------------------------------------------- | ------------ |
| s3a://warehouse/steamspy/silver/data/dt=2026-01-01/part-00001.parquet | {2026-01-01} |
| s3a://warehouse/steamspy/silver/data/dt=2026-01-01/part-00002.parquet | {2026-01-01} |


manifest-B.avro:


| file_path                                                             | partition    |
| --------------------------------------------------------------------- | ------------ |
| s3a://warehouse/steamspy/silver/data/dt=2026-01-02/part-00001.parquet | {2026-01-02} |


  


For example on the first day an iceberg table is ran the folder structure looks like...

snapshot_1
  └── manifest list
      └── manifest_A.avro  → [dt=2026-01-01 files]

On day 2 it looks like

snapshot_2
  └── manifest list  
      ├── manifest_A.avro  → [dt=2026-01-01 files]  ← reused, unchanged  
      └── manifest_B.avro  → [dt=2026-01-02 files]  ← new     

  


Iceberg reuses manifest files across snapshots. When you write 2026-01-02, the new snapshot gets a new manifest list 
that references:

- A new manifest file for the new 2026-01-02 data files                                                             
- The existing manifest file(s) from the previous snapshot (carried over by reference, not copied)

Why this matters for the replication use case:                                                                     

When you diff two snapshots, Iceberg compares their manifest lists to find which data files were added/removed.  
That's what makes incremental replication efficient, you're not scanning partition directories, you're comparing
manifest metadata. Each snapshot is self contained. 

For all intents an purposes we can think of an iceberg snapshot as a metadata file that points the data files that make up an iceberg table at a given point in time. 

---

## How The Replication Spark Job Works

The first thing to know about the replication spark job is that when it finishes writing a new snapshot to clickhouse it updates a separate state table in clickhouse. Here it uploads the snapshot_id of the snapshot just uploaded and the iceberg table the snapshot came from. This is important because one of the first things the job is query that clickhouse table to find out; what was the most recent snapshot_id replicated to clickhouse?

```
SELECT last_snapshot_id 
FROM {STATE_TABLE} FINAL 
WHERE table_name = %(table_name)s
```

  


After finding out which snapshot_id was most recently replicated into clickhouse we find the the most recently written snapshot_id to iceberg. You can this do by querying snapshots metadata table iceberg exposes. 

```
SELECT snapshot_id
FROM {iceberg_table}.snapshots
ORDER BY committed_at DESC
LIMIT 1
```

Iceberg exposes a lot of different metadata tables you can query to get differnt info about yout tables and their history. Below is a list of all the different tables but you can follow this link [here](https://iceberg.apache.org/docs/latest/spark-queries/#inspecting-tables) to learn about them from the offical docs. 


| table                      | grain                                          | description                                                                        |
| -------------------------- | ---------------------------------------------- | ---------------------------------------------------------------------------------- |
| `.history`                 | One row per snapshot                           | Timeline of table versions with ancestry and timestamps                            |
| `.snapshots`               | One row per snapshot                           | Operation type, manifest list path, and summary stats per snapshot                 |
| `.manifests`               | One row per manifest file                      | Manifest files in the current snapshot with partition range and row counts         |
| `.all_manifests`           | One row per manifest file per snapshot         | Same as `.manifests` but includes manifests from all historical snapshots          |
| `.files`                   | One row per data file                          | Physical file metadata and per-column statistics for the current snapshot          |
| `.all_data_files`          | One row per data file per snapshot             | Same as `.files` but spans all snapshots, including historical ones                |
| `.entries`                 | One row per data file per snapshot             | File-level add/delete status per snapshot — used for change detection              |
| `.all_entries`             | One row per data file across all snapshots     | Same as `.entries` but includes entries from expired and replaced snapshots        |
| `.partitions`              | One row per partition                          | Aggregate file counts, row counts, and value bounds per partition in current state |
| `.positional_delete_files` | One row per positional delete file             | Delete files that mark specific row positions for deletion                         |
| `.all_delete_files`        | One row per delete file per snapshot           | All positional and equality delete files across all snapshots                      |
| `.metadata_log_entries`    | One row per metadata file write                | History of metadata file locations written over the table's lifetime               |
| `.references`              | One row per branch or tag                      | Named references pointing to specific snapshots                                    |

<br>

Anyways for the query we just ran we get the most recently written iceberg snapshot_id by ordering by commited_at where the table looks like this.

### Snapshots Iceberg Metadata Table Example


| column        | value                                                                                                                          | description                                                                        |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------- |
| committed_at  | `2026-04-10 15:36:55.579`                                                                                                      | When this snapshot was committed                                                   |
| snapshot_id   | `2429425790902926671`                                                                                                          | Unique ID for this snapshot — this is what we store in the replication state table |
| parent_id     | `NULL`                                                                                                                         | The previous snapshot's ID (NULL for the first snapshot)                           |
| operation     | `append`                                                                                                                       | What kind of write produced this snapshot (`append`, `overwrite`, `delete`)        |
| manifest_list | `s3a://warehouse/steamspy/silver_int_publishers/metadata/snap-2429425790902926671-1-2da2c855-4736-49b8-9e05-69333759d7b6.avro` | Path to the manifest list file for this snapshot                                   |
| summary       | see below                                                                                                                      | Stats about what changed in this snapshot                                          |


**summary**

```json
{
  "added-data-files": "1",
  "added-files-size": "438824",
  "added-records": "45462",
  "changed-partition-count": "1",
  "spark.app.id": "app-20260410153605-0002",
  "total-data-files": "1",
  "total-delete-files": "0",
  "total-equality-deletes": "0",
  "total-files-size": "438824",
  "total-position-deletes": "0",
  "total-records": "45462"
}
```

<br>

Now with both of the most recent snapshot_id's from iceberg and clickhouse we can compare to see how far behind clickhouse is from iceberg. Usually by writing data using an append method you can use a built in incremental read API designed for detecting changes like so

```
SELECT * FROM table                                                             
FOR SYSTEM_VERSION BETWEEN snapshot_id_1 AND snapshot_id_2
```

<br>

This works because Iceberg tracks which data files were added in each snapshot. For APPEND operations, new files = new data. 

However this doesn't work for this pipeline because the spark jobs overwrite partitions rather than incrementally append. This is because the API source steamspy is itself a snapshot of steam game data rather than a stream like logs, transactions, etc. This means by re-ingesting from the source we're asking what is the current state right now rather than accumulating events, so it doesn't make sense to make these tables incremental. Because of this the spark job uses a different method to find differences between clickhouse and iceberg. Instead the job queries partitions values that were written to iceberg after the most recent clickhouse snapshot_id. This is done by querying the iceberg entries metadata table like so

```
SELECT DISTINCT data_file.partition.dt
FROM {iceberg_table}.entries
WHERE snapshot_id IN (
    SELECT snapshot_id
    FROM {iceberg_table}.snapshots
    WHERE snapshot_id > {last_clickhouse_snapshot_id}
)
AND status = 1
```

<br>

Since this pipeline partitions by date this query returns dates that a file was added to a snapshot after the most recently replicated clickhouse snapshot_id. In other words "which date partitions had data files written since we last replicated?" Below is an example of the entries table using `steamspy.silver_int_publishers.entries`

### Entries Iceberg Metadata Table Example

| column               | value                 | description                                                                                   |
| -------------------- | --------------------- | --------------------------------------------------------------------------------------------- |
| status               | `1`                   | Whether the file was added (1) or deleted (2) in this snapshot                                |
| snapshot_id          | `2429425790902926671` | The snapshot this file entry belongs to                                                       |
| sequence_number      | `1`                   | Global order of this operation across the table's history                                     |
| file_sequence_number | `1`                   | Order this specific file was added                                                            |
| data_file            | see below             | Physical file metadata — path, format, partition value, row count, size, and per-column stats |
| readable_metrics     | see below             | Human-readable column stats — value counts and min/max bounds per column by name              |


**data_file**

```json
{
  "content": 0,
  "file_path": "s3a://warehouse/steamspy/silver_int_publishers/data/dt=2026-03-28/00000-2-c5be4a14-0b48-4bb9-82fb-274b78f53a89-0-00001.parquet",
  "file_format": "PARQUET",
  "spec_id": 0,
  "partition": { "dt": "2026-03-28" },
  "record_count": 45462,
  "file_size_in_bytes": 438824,
  "column_sizes": { 1: 64510, 2: 372961, 3: 154 },
  "value_counts": { 1: 45462, 2: 45462, 3: 45462 },
  "null_value_counts": { 1: 0, 2: 0, 3: 0 },
  "nan_value_counts": {},
  "lower_bounds": { 1: "", 2: "!retigma studio", 3: "2026-03-28" },
  "upper_bounds": { 1: "...", 2: "ｌｅｍｏｎ　ｂａｌｍ", 3: "2026-03-28" },
  "key_metadata": null,
  "split_offsets": [4],
  "equality_ids": null,
  "sort_order_id": 0
}
```

**readable_metrics**

```json
{
  "dt": {
    "value_count": 45462,
    "null_value_count": 0,
    "nan_value_count": null,
    "lower_bound": "2026-03-28",
    "upper_bound": "2026-03-28"
  },
  "publisher": {
    "column_size": 372961,
    "value_count": 45462,
    "null_value_count": 0,
    "nan_value_count": null,
    "lower_bound": "!retigma studio",
    "upper_bound": "ｌｅｍｏｎ　ｂａｌｍ"
  },
  "publisher_id": {
    "column_size": 64510,
    "value_count": 45462,
    "null_value_count": 0,
    "nan_value_count": null,
    "lower_bound": 0,
    "upper_bound": 45461
  }
}
```

