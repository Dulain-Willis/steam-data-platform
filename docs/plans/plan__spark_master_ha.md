# Spark Master High Availability — ZooKeeper Option

## The Problem

During a rolling deploy, `spark-master` is restarted in place with `--force-recreate`. With filesystem-based recovery enabled this is safe — running jobs survive because the master reads its state from disk and workers reconnect. But there is still a brief window (seconds) where the master is down and new Spark job submissions will be rejected.

If that window is acceptable, filesystem recovery is the right call for this setup. If it needs to be truly zero-downtime for the master as well, ZooKeeper HA is the alternative.

---

## How ZooKeeper HA Works

You run two (or more) Spark master instances pointing at the same ZooKeeper ensemble. ZooKeeper elects one as the active leader. The other stays in standby, watching for the leader to go away.

When the active master goes down (or is stopped for a deploy):
- ZooKeeper detects the loss of the leader's ephemeral node
- The standby master wins election and becomes active
- Workers and drivers reconnect to the new leader
- Running jobs are unaffected — only scheduling of *new* applications pauses during the brief failover

Clients and workers discover the current leader by listing all master addresses:
```
spark://spark-master-1:7077,spark-master-2:7077
```

---

## What It Would Take Here

### New services in `compose.yml`

```yaml
  zookeeper:
    image: zookeeper:3.9
    container_name: zookeeper
    ports:
      - "2181:2181"
    restart: always

  spark-master-1:
    image: ghcr.io/dulain-willis/steam-pipelines:latest
    container_name: spark-master-1
    environment:
      SPARK_DAEMON_JAVA_OPTS: >-
        -Dspark.deploy.recoveryMode=ZOOKEEPER
        -Dspark.deploy.zookeeper.url=zookeeper:2181
        -Dspark.deploy.zookeeper.dir=/spark
    ports:
      - "7077:7077"
      - "8081:8080"
    restart: always

  spark-master-2:
    image: ghcr.io/dulain-willis/steam-pipelines:latest
    container_name: spark-master-2
    profiles: [surge]
    environment:
      SPARK_DAEMON_JAVA_OPTS: >-
        -Dspark.deploy.recoveryMode=ZOOKEEPER
        -Dspark.deploy.zookeeper.url=zookeeper:2181
        -Dspark.deploy.zookeeper.dir=/spark
    ports:
      - "7078:7077"
      - "8083:8080"
    restart: always
```

Workers and Spark job submissions would need to reference both masters:
```
spark://spark-master-1:7077,spark-master-2:7077
```

### Deploy step

Instead of restarting in place:
1. Start `spark-master-2` (surge) — ZooKeeper holds it in standby
2. Stop `spark-master-1` — ZooKeeper promotes `spark-master-2` to active, failover is automatic
3. Recreate `spark-master-1` with new image — it reconnects to ZooKeeper as standby
4. Stop `spark-master-2`

---

## Tradeoffs vs Filesystem Recovery

| | Filesystem Recovery | ZooKeeper HA |
|---|---|---|
| Master downtime during deploy | Seconds (restart window) | Zero |
| New job submissions during deploy | Rejected briefly | Unaffected |
| Running jobs during deploy | Unaffected | Unaffected |
| Complexity | Low — one config flag | High — new ZooKeeper service, dual masters, all clients updated |
| Resource cost | None | Extra container + memory |
| Right for this setup | Yes, for now | Overkill unless the master restart window becomes a real problem |

---

## Recommendation

Use filesystem recovery for now. The master restart window is seconds and only affects new job submissions, not running jobs. ZooKeeper HA makes sense if this platform grows to a point where deploys need to be completely invisible to callers or if the master becomes a frequent restart target.

---

## Links

- [Spark Standalone Mode — High Availability](https://spark.apache.org/docs/latest/spark-standalone.html#high-availability)
- [Spark Docs — Running with ZooKeeper](https://spark.apache.org/docs/latest/spark-standalone.html#standby-masters-with-zookeeper)
- [ZooKeeper Docker Image](https://hub.docker.com/_/zookeeper)
