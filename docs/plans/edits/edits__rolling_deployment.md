# Rolling Deployment Plan - Edits

## 1. No deploy lock - **COMPLETED ✅**

If two commits land in quick succession, two `deploy.sh` processes run concurrently and corrupt each other. Add a mutex at the top of the script:

```bash
exec 200>/tmp/steam-deploy.lock
flock -n 200 || { echo "Deploy already running"; exit 1; }
```

---

## 2. SSH connection drop mid-deploy - **COMPLETED ✅**

`appleboy/ssh-action` runs the script over SSH. If the connection drops (network blip, GitHub Actions timeout at 6h), the script keeps running headless with no visibility, or worse, gets killed mid-roll leaving a partial state. Wrap it in `nohup` or `tmux`/`screen`, and tail a log file:

```yaml
script: |
  nohup bash ~/steam/steam-data-platform/deploy.sh >> ~/steam-deploy.log 2>&1 &
  # then tail and wait for completion
```

---

## 3. `:latest` tag is a race condition - **COMPLETED ✅**

Between `docker pull` and `docker compose up`, another CI run could push a new `:latest`. Two permanent services could end up on different image SHAs. Pass the exact digest through the dispatch chain:

```yaml
# in repository_dispatch payload:
client_payload: '{"sha": "${{ steps.build.outputs.digest }}"}'
```

Then `deploy.sh` pulls by digest, not tag.

---

## 4. Spark master restart (Step 7) has no surge

Everything else gets a surge, but spark-master gets a raw `force-recreate`. While it restarts:
- The newly rolled spark-worker loses its master connection
- Any running Spark apps lose their driver coordination
- Submitted-but-not-started jobs are dropped

If spark-master's image didn't change (it uses `steam-pipelines`, same as worker), consider skipping the master restart entirely unless the image actually changed. If it must restart, ensure `RECOVERY_MODE=FILESYSTEM` recovery directory is mounted as a volume to survive the restart, and the worker needs retry logic to reconnect.

---

## 5. Airflow DB migrations not addressed - **COMPLETED ✅**

If the new `steam-orchestration` image bumps the Airflow version, schema migrations are needed before any new container starts. Surge containers would crash or corrupt data hitting an un-migrated DB. Add before step 2:

```bash
docker compose run --rm airflow-worker airflow db migrate
```

---

## 6. Celery prefetch buffer defeats `cancel_consumer`

By default Celery prefetches 4 tasks per worker. When `cancel_consumer` is called, those prefetched tasks are still in the worker's local buffer and will execute. Set in airflow env:

```yaml
AIRFLOW__CELERY__WORKER_PREFETCH_MULTIPLIER: 1
```

Without this, the "drain" doesn't actually drain — it just stops fetching new tasks while executing a buffer of already-claimed ones that aren't visible with `inspect active`.

---

## 7. Redis has no auth and no persistence

```yaml
redis://:@redis:6379/0  # empty password
```

If Redis crashes, the entire task queue is lost — queued tasks vanish. And any container on the Docker network can connect. Add:
- `--requirepass` with a secret from `.env`
- `appendonly yes` for AOF persistence (or at minimum RDB snapshots)

---

## 8. Abort leaves surge containers running - **COMPLETED ✅**

The abort behavior says "all un-rolled instances remain on the old image" but doesn't mention cleaning up surge containers. If deploy fails at step 6 and exits 1, both permanent and surge workers run permanently, doubling resource usage and potentially double-processing tasks. Add a `trap` cleanup:

```bash
cleanup() {
  docker compose --profile surge stop
  docker compose --profile surge rm -f
}
trap cleanup EXIT
```

Then explicitly remove the trap on success before exit 0.

---

## 9. No pre-flight checks - **COMPLETED ✅**

Before pulling images and starting surges, verify:
- All permanent services are currently healthy (don't deploy on top of a broken state)
- Sufficient disk space for new images
- Docker daemon is responsive
- No other deploy is running (ties back to #1)

---

## 10. Rollback mechanism is underspecified

The rollback says "re-runs steps 2-9 using the pinned digest" but:
- `compose.yml` references images by name, not digest — how do you actually override?
- If the DB was migrated (Airflow upgrade), rolling back the image without rolling back the DB will break
- What if the previous image has been garbage-collected from GHCR?

Need a concrete mechanism: either environment-variable image refs in compose (`image: ${ORCHESTRATION_IMAGE}`), or `docker tag` the digest to `:latest` locally before running compose.

---

## 11. Test Step 5 is empty

No tests for Traefik, which is the single entry point. At minimum:
- Verify `curl -H "Host: airflow.localhost" http://localhost/health` routes to the webserver
- Verify failover: stop `airflow-webserver`, confirm requests still route to surge
- Verify Traefik dashboard is accessible on 8090

---

## 12. No deploy notifications

At production scale, deploys should emit notifications on start, success, or failure — even with a single operator. Add a webhook (Slack/Discord/email) at the start and end of `deploy.sh`, including which image digests were deployed and how long it took.

---

## 13. Traefik router naming on surge webserver

Both webservers define the same router name `traefik.http.routers.airflow` and same service name `traefik.http.services.airflow`. This should cause Traefik to merge them into one load balancer pool (which is the desired behavior), but some Traefik versions treat duplicate router names as a conflict and drop one. Explicitly test that both backends receive traffic when both are up.
