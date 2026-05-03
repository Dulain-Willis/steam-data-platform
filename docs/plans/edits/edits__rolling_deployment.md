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

## 6. Celery prefetch buffer defeats `cancel_consumer` - **COMPLETED ✅**

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

### Explanation

The concern in edit #10 is about what happens when a deploy goes wrong and you need to go back to the previous version. The plan (Step 7, "Rollback" section at the bottom) says "re-run the deploy with the old digests," but edit #10 pointed out that the *how* was vague. Let me walk through it with an example.

#### The image name vs digest problem
Your `compose.yml` has lines like:
```yaml
image: ghcr.io/dulain-willis/steam-orchestration:latest
```
That's referencing the image **by name and tag**. The tag `:latest` is just a pointer — it can change at any time. When someone pushes a new build, `:latest` now points to a completely different image.
A **digest** is the actual identity of an image — a SHA256 hash like `sha256:abc123...`. It never changes. Think of it like this:
- **Tag** (`:latest`) = a sticky note on a locker that says "current". Someone can move the sticky note to a different locker anytime.
- **Digest** (`sha256:abc123`) = the locker number itself. It always refers to the same locker.

#### The rollback problem, by example
Say you deployed version A on Monday. It works great. On Tuesday you deploy version B and it breaks everything. You want to roll back to version A.
**Without the fix:** Your `compose.yml` says `image: steam-orchestration:latest`. But `:latest` on GHCR now points to version B (the broken one). If you just run `docker compose up`, you get version B again. You're stuck — compose doesn't know what version A was.
**With the fix (what the plan implemented):** During Monday's deploy, `deploy.sh` saved the exact digests to `~/.steam/deploys/1.sha`:
```
sha256:aaa111...   (orchestration digest for version A)
sha256:bbb222...   (pipelines digest for version A)
```
Tuesday's deploy saved `2.sha` with version B's digests. Now when you run:
```bash
./deploy.sh --rollback 1
```
The script reads `1.sha`, pulls version A **by its exact digest** (not the `:latest` tag), then tags it as `:latest` locally:
```bash
docker pull ghcr.io/dulain-willis/steam-orchestration@sha256:aaa111...
docker tag ghcr.io/dulain-willis/steam-orchestration@sha256:aaa111... ghcr.io/dulain-willis/steam-orchestration:latest
```
Now when compose sees `image: steam-orchestration:latest`, that local `:latest` tag points to version A — the known-good image. Compose never needed to change. The trick is that you swap what `:latest` points to *locally on the machine* before compose runs.

#### The other two sub-concerns in edit #10
**DB migrations:** If version B ran an Airflow database migration (changed the schema), rolling back the *image* to version A without also rolling back the *database* could break things — version A's code expects the old schema. The plan doesn't fully solve this yet (it's listed as a known gap).
**Garbage collection:** GHCR can delete old images. If version A's digest was cleaned up from the registry, `docker pull @sha256:aaa111...` would fail and the rollback is impossible. This is mitigated by the fact that the images were already pulled during the original deploy and may still be cached locally, but it's not guaranteed.

#### Where this fits in the plan
Look at Step 7 in the plan — the very bottom has the "Rollback" section (lines 797-809) and the "digest writing" section (lines 772-795). That's the concrete implementation that resolved edit #10's complaint. The deploy script saves digests on success and reads them back on `--rollback`, using the pull-then-tag trick so compose.yml never needs to be modified.

---

## 11. Test Step 5 is empty - **COMPLETED ✅**

No tests for Traefik, which is the single entry point. At minimum:
- Verify `curl -H "Host: airflow.localhost" http://localhost/health` routes to the webserver
- Verify failover: stop `airflow-webserver`, confirm requests still route to surge
- Verify Traefik dashboard is accessible on 8090

---

## 12. No deploy notifications

At production scale, deploys should emit notifications on start, success, or failure — even with a single operator. Add a webhook (Slack/Discord/email) at the start and end of `deploy.sh`, including which image digests were deployed and how long it took.

---

## 13. Traefik router naming on surge webserver **COMPLETED ✅**

Both webservers currently define the same router name `traefik.http.routers.airflow` and same service name `traefik.http.services.airflow`. The intent is for Traefik to merge them into one load balancer pool so traffic flows to whichever backend is healthy. However, this is not safe to rely on.

### What the official docs say

Traefik's Docker provider documentation ([v3.0 Docker routing](https://doc.traefik.io/traefik/v3.0/routing/providers/docker/)) confirms that **services** auto-aggregate: when multiple containers share the same service name, each container's IP is added as a backend server in that service's load balancer pool. This is the mechanism that makes zero-downtime failover work — Traefik sees two healthy containers behind the `airflow` service and round-robins between them.

**Routers** are a different story. The docs do not explicitly guarantee that two containers declaring the same router name with identical configuration will merge cleanly. In practice, GitHub issues [#8694](https://github.com/traefik/traefik/issues/8694) and [#8453](https://github.com/traefik/traefik/issues/8453) report "router defined multiple times with different configurations" errors when multiple containers register the same router name. Even when the configurations are byte-for-byte identical (same rule, same service reference), some users still hit conflicts depending on the order containers are discovered by the Docker provider.

### The fix

Give each webserver a **unique router name** but point both routers at the **same shared service name**. This way each container registers its own router (no duplication conflict), but both routers resolve to the single `airflow` service, which Traefik automatically populates with every container that declares it. The load balancing and failover behavior is identical — the only difference is that router discovery is now conflict-free.

```yaml
# airflow-webserver (permanent)
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.airflow-primary.rule=Host(`airflow.localhost`)"
  - "traefik.http.routers.airflow-primary.service=airflow"
  - "traefik.http.services.airflow.loadbalancer.server.port=8080"

# airflow-webserver-surge
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.airflow-surge.rule=Host(`airflow.localhost`)"
  - "traefik.http.routers.airflow-surge.service=airflow"
  - "traefik.http.services.airflow.loadbalancer.server.port=8080"
```

The key addition is `traefik.http.routers.<name>.service=airflow` — this explicitly tells each uniquely-named router which service to forward to. Without it, Traefik would auto-generate a separate service per router, defeating the shared pool. With it, both `airflow-primary` and `airflow-surge` routers feed into the single `airflow` service that aggregates both container backends.

Update the labels in `compose.yml` for `airflow-webserver` now, and apply the surge labels when `airflow-webserver-surge` is added in Step 3. Also update the label blocks shown in Step 5 of the deployment plan to match.

### Test: verify both backends share a single load balancer pool

Even with unique router names, explicitly confirm that Traefik is routing both containers through the same service backend — not silently creating two separate services. With both webservers running:

```bash
# 1. Check that the Traefik API shows exactly one service named "airflow" with two backend servers
curl -s http://localhost:8090/api/http/services | jq '.[] | select(.name | startswith("airflow")) | {name, servers: [.loadBalancer.servers[].url]}'
# expected: one service with two server URLs (one per container)

# 2. Hit the endpoint multiple times and confirm responses come from different backends
for i in $(seq 1 10); do
  curl -s -H "Host: airflow.localhost" http://localhost/health -D - -o /dev/null 2>&1 | grep -i "x-served-by\|server:"
done
# If Traefik is round-robining, you should see responses from both container IPs.
# Alternatively, check Traefik access logs or the dashboard at http://localhost:8090 to see traffic hitting both servers.

# 3. Confirm no duplicate or conflicting services exist
curl -s http://localhost:8090/api/http/services | jq '[.[] | select(.name | contains("airflow"))] | length'
# expected: 1 (not 2 — two would mean the routers created separate auto-named services instead of sharing one)
```

If test 3 returns 2 services, the `service=airflow` label isn't being respected and Traefik is auto-generating per-router services — check the label syntax.
