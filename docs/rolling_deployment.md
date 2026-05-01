The current state of this data platform at this time is this. The repo `steam-pipelines` holding pipeline logic and spark job code is a dependency for `steam-orchestration` which is an airflow repo. Currently there's a CICD pipeline that triggers when `steam-pipelines` has a commit pushed to main. When this happens it pushes a new docker image of `steam-pipelines` tagged :latest to github container registry (ghcr). The airflow repo's dockerfile does pull from that container registry but it's manual. When an update happens you have to stop the container rebuild and docker compose up. That is not production like and won't work. The solution is a rolling deployment CICD pipeline. When a commit is pushed to main on a dependency of the airflow repo it automatically rebuild and updates itself. 

Rolling deployment means replacing running instances one at a time, or in small batches, while the remaining healthy instances keep serving traffic or doing work. For example, if a service has several workers, you start or swap one worker onto the new image, wait until it is healthy, then continue replacing the others until all instances are on the new version.

Links to inspiration

- [Grab Engineering - Zero-Downtime Airflow on EKS](https://engineering.grab.com/the-journey-of-deploying-apache-airflow-at-Grab)
- [Flatiron Health - Upgrading Airflow with Zero Downtime (Celery drain approach)](https://medium.com/flatiron-engineering/upgrading-airflow-with-zero-downtime-8df303760c96)
- [Slack Engineering - Reliably Upgrading Airflow at Scale](https://slack.engineering/reliably-upgrading-apache-airflow-at-slacks-scale/)
- [Slack Engineering - Migrating Airflow to Python 3 Without Disruption](https://slack.engineering/migrating-slack-airflow-to-python-3-without-disruption/)
- [Shopify Engineering - Lessons Learned Running Airflow at Scale](https://shopify.engineering/lessons-learned-apache-airflow-scale)
- [Airflow Docs - Production Deployment](https://airflow.apache.org/docs/apache-airflow/stable/administration-and-deployment/production-deployment.html)
- [Airflow Docs - Scheduler HA & Task Adoption](https://airflow.apache.org/docs/apache-airflow/stable/administration-and-deployment/scheduler.html)
- [Waiting for Code - What's New in Apache Spark 3.1: Nodes Decommissioning](https://www.waitingforcode.com/apache-spark/what-new-apache-spark-3.1-nodes-decommissioning/read) — SIGPWR drain + `/workers/kill` endpoint used for graceful Spark worker rolling
- [Spark Docs - Standalone Mode](https://spark.apache.org/docs/latest/spark-standalone.html) — confirms `/workers/kill` endpoint and `spark.master.ui.decommission.allow.mode` config


For this platform we will roll the docker containers which rely on newly built images. Here Airflow webserver and Airflow scheduler depend on `steam-orchestration`, while Spark master and Spark worker rely on `steam-pipelines`. This platform doesn't have multiple instances of services on purpose as were attempting to be lean being that it's running off one machine so we'll make use of surge containers. These are temporary containers started only during a deployment meaning docker compose up doesn't bring them up, but only when you call them specifically. Separate from the surge solution we will also need to add some new services expanding the complexity of the airflow service as a whole.

Push  tosteam-pipelinesmain                                                                                                                                                                                             
  → pipelines docker-publish.yml builds + pushes image                                                                                                                                                                         
    → repository_dispatch to steam-orchestration
      → orchestration docker-publish.yml builds + pushes image
        → repository_dispatch to steam-data-platform
          → steam-data-platform/deploy.yml triggers
            → appleboy/ssh-action SSHes into prod server
              → runs `bash deploy.sh` on the server

Right now Airflow runs on **LocalExecutor**, where tasks execute as subprocesses directly inside the scheduler. This means the airflow scheduler is doing two jobs. It's deciding what to run AND actually being the thing that runs it. This is fine for a single instance but it's a problem for rolling deployments. When we restart the scheduler to rebuild on a new airflow image, every task currently running dies with it. This means there's no way to drain the tasks gracefully, meaning stop accepting new work finish what you're already doing then shut down, because the scheduler and the worker are the same process. The fix is switching from **LocalExecutor** to **CeleryExecutor**, which separates those two responsibilities. Then scheduler's only job becomes deciding what tasks to queue. On top of that add a separate **Airflow worker** container that picks tasks off that queue and executes them. For the scheduler and worker to communicate through a queue we need a message broker. For this step add **Redis**. It sits between the scheduler and worker — the scheduler writes tasks to it, the worker reads from it.


## Step 1 ##
The first step is expanding the airflow service to add new containers and update configuration accordingly

### Redis ###
Since were adding an airflow worker we a message broker to communicate between the airflow scheduler and worker

- Add Redis to the `compose.yml`
```yaml
  redis:
    container_name: redis
    image: redis:7.2-bookworm
    expose:
      - 6379
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 30s
      retries: 50
      start_period: 30s
    restart: always
```
### Airflow Worker ###

- Add a Airflow Worker service to the `compose.yml`
```yaml
  airflow-worker:
    <<: *airflow-common
    command: celery worker
    healthcheck:
      test: ["CMD-SHELL", 'celery --app airflow.providers.celery.executors.celery_executor.app inspect ping -d "celery@$${HOSTNAME}" || celery --app airflow.executors.celery_executor.app inspect ping -d "celery@$${HOSTNAME}"']
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
    environment:
      <<: *airflow-common-env
      DUMB_INIT_SETSID: "0"
    restart: always
    depends_on:
      <<: *airflow-common-depends-on
      airflow-apiserver:
        condition: service_healthy
      airflow-init:
        condition: service_completed_successfully
```

### x-airflow-common ###

- Change `AIRFLOW__CORE__EXECUTOR` from `LocalExecutor` to `CeleryExecutor`
- Add the env variables for celery
```yaml
    AIRFLOW__CELERY__RESULT_BACKEND: db+postgresql+psycopg2://postgres:postgres@postgres:5432/postgres
    AIRFLOW__CELERY__BROKER_URL: redis://:@redis:6379/0
```
- Label the environment block as `&airflow-common-env` 
- Extract the `depends_on` block into a named anchor `&airflow-common-depends-on` 
- Add `redis` to the common `depends_on` with `condition: service_healthy` 
- Change the existing `postgres` entry in `depends_on` to also use `condition: service_healthy` 

### Postgres ###
Since were adding a depends on service healthy for postgres in airflow common there actually needs to be a healthcheck or this will just fail and every container that depends on it which is all will error

- Add a healthcheck so `depends_on: condition: service_healthy` 
```yaml
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "airflow"]
      interval: 10s
      retries: 5
      start_period: 5s
    restart: always
```

### Airflow Scheduler ###

- Update the scheduler service to look like
```yaml
  airflow-scheduler:
    <<: *airflow-common
    command: scheduler
    container_name: airflow-scheduler
    healthcheck:
      test: ["CMD", "curl", "--fail", "http://localhost:8974/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
    restart: always
    depends_on:
      <<: *airflow-common-depends-on
      airflow-init:
        condition: service_completed_successfully

```

## Test Step 1 ## 
Before moving on lets test all the added services are up and working. Let's also test the worker can actually communicate to the scheduler through redis. 

**1. Check all containers are up and healthy**
```bash
docker compose ps
```
Redis, airflow-worker should show as `healthy`. No service should be in `restarting` state.

**2. Verify Redis is responding**
```bash
docker exec redis redis-cli ping
# expected: PONG
```

**3. Verify the worker is alive and connected to Redis**
```bash
docker exec airflow-worker celery --app airflow.providers.celery.executors.celery_executor.app inspect ping
# expected: something like {"celery@<hostname>": {"ok": "pong"}}
```
If this returns nothing or times out, the worker failed to connect to Redis — check the broker URL in `x-airflow-common`.

**4. Verify the scheduler can see the worker**

Go to the Airflow UI → `http://localhost:8080` → top menu → **Browse > Workers**. The worker should appear there as healthy. This confirms the full chain: scheduler ↔ Redis ↔ worker.

**5. Prove the worker actually executes tasks**

Trigger any existing DAG manually from the UI and watch a task run. Check the task logs — they will show which worker picked it up:
```
Running on worker: celery@<container-hostname>
```
If tasks complete successfully the full pipeline is working.

## Step 2 ##
Later on in this plan we'll add functionality so when we bring up a new spark worker on the new docker imgage we'll "drain" the other one. Spark has a built in way to do this by making it so it stops taking new tasks, finished the current ones, and then gets killed. However, we have to add to our spark config.

- Create `steam-pipelines/docker/conf/spark-defaults.conf`:
```
spark.decommission.enabled  true
```

- Then add this line to `steam-pipelines/Dockerfile` after the existing `COPY` statements:
```dockerfile
COPY docker/conf/spark-defaults.conf /opt/spark/conf/spark-defaults.conf
```
This file is read by the Spark worker daemon on startup. Without it, sending SIGPWR to the worker does nothing.

- Commit and push these changes to `steam-pipelines` main to trigger a new image build

- 

## Test Step 2 ##

Note: since `spark-defaults.conf` is baked into the image at build time, you need to rebuild the `steam-pipelines` image after adding the file — the config won't appear in an existing running container.

**1. Verify the config file is present in the running container**
```bash
docker exec spark-worker cat /opt/spark/conf/spark-defaults.conf
# expected: spark.decommission.enabled  true
```

**2. Smoke-test the actual SIGPWR behavior**

Send the decommission signal and check the worker logs for a drain message. This is the real proof — without `spark.decommission.enabled=true`, SIGPWR is silently ignored.
```bash
docker kill --signal SIGPWR spark-worker
docker logs spark-worker 2>&1 | grep -i decommission
# expected: log line like "Decommission signal received" or "Decommissioning worker"
```

## Step 3 ##
To make this work we will bring up 4 different surge containers 

### Airflow Webserver ###
First airflow webserver. We will build a temporary webserver container. This is becuase with only one, when the container is being rebuilt and restarted during a deployment the webserver would just be down. This is not production-like. From the users perspective we don't want them to know anything is happening. 

To do this 
- Create a second copy of the airflow webserver container and call it airflow-webserver-2
- Add to the compose.yml service profiles: [surge] 
- expose it to port 8082:8080 rather than 8080:8080

### Airflow Scheduler ### 

- Create a second copy of the airflow scheduler container and call it airflow-scheduler-2
- Add to the compose.yml service profiles: [surge] 

### Airflow Worker ###
Without a surge worker there would be a gap between the old worker draining and the new one starting where no tasks can be executed. The surge worker starts on the new image first, picks up new tasks immediately, while the old worker finishes whatever it's currently running before being removed.

- Create a second copy of the airflow worker container and call it airflow-worker-surge
- Add `profiles: [surge]`

### Spark Worker ###

- Create a second copy of the spark-worker container and call it spark-worker-surge
- Add `profiles: [surge]`

## Test Step 3 ##

**1. Verify surge containers don't start with a normal `docker compose up`**
```bash
docker compose up -d
docker compose ps
```
None of the surge containers should appear. Confirms `profiles: [surge]` is working.

**2. Manually bring up all surge containers**
```bash
docker compose --profile surge up -d
```

**3. Verify surge containers are healthy**
```bash
docker compose ps
```
`airflow-webserver-surge`, `airflow-scheduler-surge`, `airflow-worker-surge`, and `spark-worker-surge` should all show as `healthy`.

**4. Verify the webserver surge is reachable**
```bash
curl -sf http://localhost:8082/health
# expected: HTTP 200 with {"metadatabase": {"status": "healthy"}, "scheduler": {"status": "healthy"}}
```

**5. Verify the worker surge is alive and connected**
```bash
docker exec airflow-worker-surge celery --app airflow.providers.celery.executors.celery_executor.app inspect ping
# expected: pong response from celery@airflow-worker-surge
```
Both the permanent worker and the surge worker should now respond — confirming two workers can run simultaneously on the same queue.

**6. Verify the spark worker surge joined the cluster**
```bash
docker exec spark-master curl -s http://localhost:8080/json | python3 -c "import sys,json; workers=json.load(sys.stdin)['workers']; print(len(workers), 'workers')"
# expected: 2 workers
```

**7. Tear down surge containers**
```bash
docker compose --profile surge stop airflow-webserver-surge airflow-scheduler-surge airflow-worker-surge spark-worker-surge
docker compose --profile surge rm -f airflow-webserver-surge airflow-scheduler-surge airflow-worker-surge spark-worker-surge
```
Confirm only the permanent services remain running with `docker compose ps`.

## Step 4 ##

We need to edit the setup.sh in `steam-data-platform` to a few different things. First we want to automatically copy the .env.example file to a .env file if it doesn't already exist. We also need to to generate a ferent and secret key to put in the .env file for airflow.

### airflow-common-env
In Apache Airflow, the Fernet key is used to encrypt sensitive data stored in the metadata database, such as connection passwords, variables, and any XCom values marked as sensitive; if it’s not set, those values are simply stored in plaintext in psotgres. In a single-instance setup this often goes unnoticed, but in a multi-instance setup (like two webservers), both instances must share the exact same Fernet key so they can decrypt each other’s data. Separately, the AIRFLOW_WEBSERVER__SECRET_KEY is a Flask session signing key used by the webserver to sign user session cookies. This becomes critical with multiple webservers behind something like a load balancer (e.g., Traefik), because a user might authenticate against one instance and then get routed to another; if the secret keys differ, the second instance will reject the cookie and log the user out. Previously, this worked because Airflow auto-generates both keys at startup and you only had one instance, so there was no cross-instance conflict, and restarts were infrequent enough that you didn’t notice the implications of those keys changing.

- Update &airflow-common-env to have env variables for two new keys
```yaml
AIRFLOW__CORE__FERNET_KEY: ${AIRFLOW_FERNET_KEY}
AIRFLOW__WEBSERVER__SECRET_KEY: ${AIRFLOW_SECRET_KEY}
```
- Update .env.example to have this in the airflow section of the file
```sh
# Auto-generated by setup.sh — do not set manually
AIRFLOW_FERNET_KEY=
AIRFLOW_SECRET_KEY=
```
- Add code to make the setup.sh file to copy the .env.example file to an separate file called .env 
- Add code to setup.sh to generate fernet key and copy it to the .env file where the placeholder is
- Add code to setup.sh to generate a secret key using openssl rand hex 32 and relace the secret key place holder

## Step 5 ##

Since you don't want consumers of any of these sytems to know anything is happening during a deployment we need to configure the service they consume. This is going to be the webserver UI. When we start the surge container for the webserver during a deployment jsut because it's there doesn't mean when people go to the UI it will just work becuase all the systems are configured to use port 8080 UI while the surge is 8082. This means it the UI will just be down while the surge container just exists on another port. The solution is a reverse proxy. We'll traefik so instead of going to port 8080 we go to traefik's port 80 everytime. Then becasue of the rules we configure Traefik knows when someone is trying to access the airflow UI send their request to 8080. It's also connected to the Docker socket so it knows when the 8080 airflow UI dies to instead send airflow requests to the other webserver 8082. 

### Add Traefik ###
- Add Trafik as a service to the docker compose 
```yaml
  traefik:
    image: traefik:v3
    container_name: traefik
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedByDefault=false"
      - "--entrypoints.web.address=:80"
      - "--api.dashboard=true"
    ports:
      - "80:80"
      - "8090:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
```
- Be sure to mount the docker socket
- Be sure to expose 8090 to host for dashboard
- Be sure exposed default is false

### airflow-webserver ###
Since we configured `- "--providers.docker.exposedByDefault=false"` we need to specify which containers we want Traefik to read the metadata on to find out its ports, names, etc. from the docker socket connection

- Add labels to webserver service to enable detection define host rule and port. We enable this container to be watched by Traefik. 
```   labels:
      - "traefik.enable=true"
      - "traefik.http.routers.airflow.rule=Host(`airflow.localhost`)"
      - "traefik.http.services.airflow.loadbalancer.server.port=8080"
```

### airflow-webserver-surge ###
Since we configured `- "--providers.docker.exposedByDefault=false"` we need to specify which containers we want Traefik to read the metadata on to find out its ports, names, etc. from the docker socket connection

- Add labels to webserver service to enable detection define host rule and port. We enable this container to be watched by Traefik. 
```   labels:
      - "traefik.enable=true"
      - "traefik.http.routers.airflow.rule=Host(`airflow.localhost`)"
      - "traefik.http.services.airflow.loadbalancer.server.port=8080"
```

## Test Step 5 ##


## Step 6 ##
Right now both `steam-pipelines` and `steam-orchestration` push new image builds on commits to main, but they're not connected. Let's add code to the bottom of the file CICD Github Actions file that when `steam-pipelines` pushes a new image to Github it triggers to `steam-orchestration` to rebuild it's docker image using that new `steam-pipelines` image. 

### Steam Pipelines ### 
- After the `build-and-push` step succeeds, add a step that dispatches a `repository_dispatch` event to `steam-orchestration`:
```yaml
- name: Trigger orchestration build
  if: success()
  uses: peter-evans/repository-dispatch@v3
  with:
    token: ${{ secrets.GH_DISPATCH_TOKEN }}
    repository: Dulain-Willis/steam-orchestration
    event-type: pipelines-updated
```

### Steam Orchestration ###
- Add `repository_dispatch` trigger (in addition to existing `push`/`workflow_dispatch`) and add dispatch step to `steam-data-platform` after successful build:
```yaml
on:
  push:
    branches: [main]
  workflow_dispatch:
  repository_dispatch:
    types: [pipelines-updated]

# after build-and-push step:
- name: Trigger deployment
  if: success()
  uses: peter-evans/repository-dispatch@v3
  with:
    token: ${{ secrets.GH_DISPATCH_TOKEN }}
    repository: Dulain-Willis/steam-data-platform
    event-type: deploy
```

## Step 7 ##
At this point we've configured everything so that when steam pipelines pushes a commit to main the CICD pipelines work together to push a new steam-pipelines docker image to ghcr which triggers Github to rebuild the steam-orchestration docker image and store again in ghcr. Now we need a way to deploy this so when I'm on my machine it actually takes those two new iamges and rebuilds the running containers live with no interuptions. We'll do this with a script, deploy.sh

### steam-data-platform GH Actions script ###
In the previous step when steam-orchestration is updated it triggers `steam-data-platform`. This file will be the response to that trigger. It says okay `steam-orchestration` was just udpated to deploy the images by running deploy.sh

### Github Actions ###
- Write the deploy.yml to `steam-data-platform/.github/workflows/deploy.yml`
```yaml
on:
  repository_dispatch:
    types: [deploy]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to production
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.DEPLOY_HOST }}
          username: ${{ secrets.DEPLOY_USER }}
          key: ${{ secrets.DEPLOY_SSH_KEY }}
          script: |
            cd ~/steam/steam-data-platform
            git pull origin main
            bash deploy.sh
```

### Write deploy script ###
Now it's time to right the deploy script. This is the main thing that actually ties eveything together. It follows this format. Through github actions the script above ssh's into the host server, in this case just my computer, and runs the deploy.sh. It pulls those new images that triggered this deployment to begin with and then records them

- Full rolling deploy logic, runs on the production machine. Key behaviors:

**Normal deploy (`./deploy.sh`):**

**1. Pull images from GHCR** (pre-built by GitHub Actions — no build step on the server):
- The first thing we'll do is pull the newly built images from ghcr onto the host server
```bash
docker pull ghcr.io/dulain-willis/steam-orchestration:latest
docker pull ghcr.io/dulain-willis/steam-pipelines:latest
```



**2. Bring up ALL surge containers**

All services with `profiles: [surge]` start — no need to name them individually.
```bash
docker compose --profile surge up -d --no-deps
```

**3. Wait for all surge containers to report healthy via Docker healthcheck**

Poll `docker inspect --format='{{.State.Health.Status}}' <container>` == `"healthy"` for each, with its own timeout:
- `airflow-worker-surge` — 60s timeout
- `spark-worker-surge` — 60s timeout
- `airflow-scheduler-2` — 120s timeout
- `airflow-webserver-2` — 120s timeout

→ Abort + exit 1 if any container times out (permanents untouched)

**4. Verify surge containers are actually serving correctly**

a. `airflow-worker-surge` — confirms connected to Redis and ready to accept tasks:
```bash
docker exec airflow-worker-surge celery \
  --app airflow.providers.celery.executors.celery_executor.app \
  inspect ping -d celery@airflow-worker-surge
```

b. `spark-worker-surge` — worker count must be greater than before surge started (confirms registration with Spark master):
```bash
curl -s http://localhost:8080/json | jq '.workers | length'
```

c. `airflow-scheduler-2` — confirms scheduler is running and writing heartbeats:
```bash
docker exec airflow-scheduler-2 airflow jobs check --job-type SchedulerJob --limit 1
```

d. `airflow-webserver-2` — confirms webserver is up and metadata DB connection is healthy:
```bash
curl -sf http://localhost:8082/health
```

→ Abort + exit 1 if any check fails

**5. Roll airflow-worker**

a. Stop old worker accepting new tasks (airflow-worker-surge picks up all new tasks):
```bash
docker exec airflow-worker celery \
  --app airflow.providers.celery.executors.celery_executor.app \
  control cancel_consumer default
```

b. Poll until no tasks are actively running on old worker (300s timeout, 5s interval — allows long Spark submits to finish):
```bash
docker exec airflow-worker celery \
  --app airflow.providers.celery.executors.celery_executor.app \
  inspect active --timeout 5
```
→ Abort + exit 1 if timeout

c. Stop and remove old worker, bring up permanent on new image:
```bash
docker compose stop airflow-worker && docker compose rm -f airflow-worker
docker compose up -d --no-deps --force-recreate airflow-worker
```

d. Poll Docker healthcheck on `airflow-worker` == `"healthy"` (60s timeout), then confirm connected:
```bash
docker exec airflow-worker celery \
  --app airflow.providers.celery.executors.celery_executor.app \
  inspect ping -d celery@airflow-worker
```

e. Drain `airflow-worker-surge` before removing it — it may have picked up tasks while the old worker was draining:
```bash
docker exec airflow-worker-surge celery \
  --app airflow.providers.celery.executors.celery_executor.app \
  control cancel_consumer default
```

f. Poll until no tasks are actively running on `airflow-worker-surge` (300s timeout, 5s interval):
```bash
docker exec airflow-worker-surge celery \
  --app airflow.providers.celery.executors.celery_executor.app \
  inspect active --timeout 5
```
→ Abort + exit 1 if timeout

g. Remove surge worker:
```bash
docker compose stop airflow-worker-surge && docker compose rm -f airflow-worker-surge
```

**6. Roll spark-worker**

a. Send SIGPWR to stop old worker accepting new tasks (requires `spark.decommission.enabled=true`):
```bash
docker kill --signal SIGPWR spark-worker
```

b. Poll until no active tasks remain on `spark-worker` across all running apps (300s timeout, 5s interval):
```bash
APPS=$(curl -s http://localhost:8080/api/v1/applications | jq -r '.[] | select(.status=="RUNNING") | .id')
# for each APP_ID:
curl -s http://localhost:8080/api/v1/applications/$APP_ID/executors \
  | jq '[.[] | select(.hostPort | startswith("spark-worker:")) | .activeTasks] | add // 0'
# sum across all apps must equal 0
```
→ Abort + exit 1 if timeout

c. Stop and remove old worker, bring up permanent on new image:
```bash
docker compose stop spark-worker && docker compose rm -f spark-worker
docker compose up -d --no-deps --force-recreate spark-worker
```

d. Poll spark-master `/json` until `spark-worker` re-registers (60s timeout):
```bash
curl -s http://localhost:8080/json | jq '.workers[].id'
```

e. Drain `spark-worker-surge` before removing it — it may have picked up tasks while the old worker was draining:
```bash
docker kill --signal SIGPWR spark-worker-surge
```

f. Poll until no active tasks remain on `spark-worker-surge` across all running apps (300s timeout, 5s interval):
```bash
# for each APP_ID:
curl -s http://localhost:8080/api/v1/applications/$APP_ID/executors \
  | jq '[.[] | select(.hostPort | startswith("spark-worker-surge:")) | .activeTasks] | add // 0'
# sum across all apps must equal 0
```
→ Abort + exit 1 if timeout

g. Remove surge worker:
```bash
docker compose stop spark-worker-surge && docker compose rm -f spark-worker-surge
```

**7. Restart spark-master**

Filesystem recovery mode preserves running job state across the restart:
```bash
docker compose up -d --no-deps --force-recreate spark-master
```

**8. Roll airflow-scheduler-1**

a. Recreate on new image:
```bash
docker compose up -d --no-deps --force-recreate airflow-scheduler-1
```

b. Poll until healthy (120s timeout, 5s interval):
```bash
docker exec airflow-scheduler-1 airflow jobs check --job-type SchedulerJob --limit 1
```
→ Abort + exit 1 if timeout

c. Remove surge scheduler:
```bash
docker compose stop airflow-scheduler-2 && docker compose rm -f airflow-scheduler-2
```

**9. Roll airflow-webserver-1**

a. Recreate on new image:
```bash
docker compose up -d --no-deps --force-recreate airflow-webserver-1
```

b. Poll until healthy (120s timeout, 5s interval):
```bash
curl -sf http://localhost:8080/health
```
→ Abort + exit 1 if timeout

c. Remove surge webserver:
```bash
docker compose stop airflow-webserver-2 && docker compose rm -f airflow-webserver-2
```

**10. Write digest and exit 0** — only primary instances running

Deploy succeeded. Write the digests of the images just deployed:
```bash
mkdir -p ~/.steam/deploys
NEXT=$(ls ~/.steam/deploys/*.sha 2>/dev/null | wc -l)
NEXT=$((NEXT + 1))
docker inspect --format='{{.RepoDigests}}' \
  ghcr.io/dulain-willis/steam-orchestration:latest \
  ghcr.io/dulain-willis/steam-pipelines:latest > ~/.steam/deploys/${NEXT}.sha

# Keep only the last 5 — remove the oldest if over the limit
ls -t ~/.steam/deploys/*.sha | tail -n +6 | xargs -r rm
```

If `~/.steam/deploys/` does not exist or is empty (first deploy), skip straight to writing file `1.sha` — nothing to roll back to yet.

**Rollback (`./deploy.sh --rollback [N]`):**

Reads the Nth most recent digest file (defaults to 1 = previous deploy):
```bash
SHA_FILE=$(ls -t ~/.steam/deploys/*.sha | sed -n "${N}p")
```
Re-runs steps 2–9 using the pinned digest instead of `:latest`. Same health check gates.

**Abort behavior:**
- Logs last 50 lines of the failed container
- All un-rolled instances remain on the old image (no action needed)
- Exit 1