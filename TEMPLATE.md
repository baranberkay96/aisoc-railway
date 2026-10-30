# AiSOC v20 AI Security Operations Center — Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **AiSOC v20 AI Security Operations Center** (version label `20` = AiSOC major; release `v20.3.0`) |
| Description | Ingest security alerts, correlate threats and triage them with AI agents. (73 chars) |
| Category | AI/ML |
| Tags | aisoc, soc, security, siem, threat-detection, incident-response, ai-agents, llm, ollama, kafka, clickhouse, self-hosted |
| Icon | `https://cdn.jsdelivr.net/npm/lucide-static@1.59.0/icons/shield-check.svg` (Lucide, ISC). Not the AiSOC logo: upstream's TRADEMARK.md does not grant use of the logo as third-party branding. |
| User input at deploy | **None.** The administrator password, 9 service secrets, the credential-vault key and all datastore passwords are generated. An LLM key is optional (a local model ships with the template). |

The listing name and description are used as given. Everything the description promises is delivered: telemetry ingest (authenticated push API, connectors, sample data), detection and correlation (fusion), and AI triage (agents with a local model, or a hosted provider).

## Base

No marketplace template exists for AiSOC. Upstream's own `infra/railway/` guide deploys a four-service **demo** profile (`ENVIRONMENT=demo`, Kafka/ClickHouse/Neo4j/Qdrant disabled, seeded demo data with a published demo login) — not the product pipeline, so it was read and not used.

This template follows upstream's **production** command, `docker compose -f docker-compose.yml -f docker-compose.prod.yml`, at **v20.3.0** (tag commit `e3edeb8`, released 2026-10-30), with the `full` profile's stores and workers switched on as `make up-full` does (`AISOC_LAKE_WRITER_ENABLED=true`, `AISOC_GRAPH_ENABLED=true`). The local `_upstream` copy was compared with the tag (git blob hashes of both compose files, the LiteLLM config, the ClickHouse init SQL, the console's `next.config.js`, the admin bootstrap, the migration runner, the sample-data loader, the ingest router, `VERSION`, `LICENSE`: all identical).

## Pinned versions (checked 2026-10-30)

| Service | Image | Tag | Built | Notes |
|---|---|---|---|---|
| web, api, ingest, fusion, agents, actions, connectors, threatintel, realtime, enrichment, ueba | `ghcr.io/beenuar/aisoc-<svc>` (`aisoc-core-api` for api) | `v20.3.0` | 2026-10-28…30 | Image label `org.opencontainers.image.revision=e3edeb85…` = the v20.3.0 tag. linux/amd64 + arm64. |
| litellm (repo build) | `ghcr.io/berriai/litellm` | `v1.102.1@sha256:87f34979…` | 2026-09-23 | Upstream's pin. |
| ollama (repo build) | `ollama/ollama` | `0.40.3@sha256:adca95a1…` | 2026-10-11 | Upstream pins 0.6.7 (see Deviations). Same digest as our Odysseus template. |
| clickhouse (repo build) | `clickhouse/clickhouse-server` | `23.8.16.16@sha256:1bf47c68…` | 2024-08-20 | Upstream line 23.8, last patch. |
| opensearch (repo build) | `opensearchproject/opensearch` | `2.11.1@sha256:cbca8e35…` | 2024-02-15 | Upstream line 2.11 (2.11.0), last patch. |
| neo4j | `neo4j` | `5.15.0-community` | 2024-01-17 | Upstream `5.15-community`, pinned to its patch. |
| qdrant | `qdrant/qdrant` | `v1.19.2` | 2026-10-05 | Upstream pins v1.7.0 (see Deviations). |
| kafka | `redpandadata/redpanda` | `v24.3.18` | 2025-07-16 | Kafka-API broker replacing cp-kafka 7.5.0 + ZooKeeper (see Deviations). |
| Postgres | `ghcr.io/railwayapp-templates/postgres-ssl` | `18` | 2026-10-23 | Railway base (PostgreSQL 18.6). Upstream uses postgres:16-alpine. |
| Redis | `redis` | `8.2.11` | 2026-10-28 | Railway base definition, pinned to the current 8.2 patch. Upstream uses redis:7-alpine. |
| Local model | `llama3.2:3b-instruct-q4_K_M` (Ollama library, ~2 GB) | | | Upstream's pinned CPU model. Pulled on first boot. |

**Upgrades:** change the tag on all eleven `ghcr.io/beenuar/aisoc-*` images together (they are released as one version) and redeploy. The api pre-deploy step applies new SQL migrations (strict: a failed migration fails the deploy), UEBA applies its own Alembic chain at start, and the api applies ClickHouse lake migrations at start. Read upstream's RELEASES.md first; AiSOC ships often. Third-party versions live in the four Dockerfiles under `services/` and in the image fields of `template.json`.

## Architecture

```
Internet ──HTTPS──▶ web :3000 (Next.js console; proxies /api/v1, /auth, /ws, /sse server-side)
   │                  ├─▶ api :8000 ── Postgres (aisoc_app, RLS) · Redis · Kafka · ClickHouse · Neo4j · Qdrant
   │                  ├─▶ agents :8084 (copilot, hunts, playbooks)
   │                  └─▶ realtime :8086 (WebSocket/SSE tickets)
   │
   └──HTTPS──▶ ingest :8080 (POST /v1/ingest[/batch], /v1/inbox/*; token required)
                  └─▶ Kafka aisoc.raw_events ─▶ fusion :8003 (2.5k executable detections, correlation)
                         ├─▶ ClickHouse (event lake, via on-disk spool)   ├─▶ Postgres alerts ─▶ realtime ─▶ console
                         └─▶ Kafka aisoc.alerts.fused ─▶ agents (auto-triage via litellm ─▶ ollama / hosted LLM)
                                                           └─▶ actions :8085 (proposals; human approval before any vendor change)
   connectors :8003 (80+ vendor pollers, encrypted credentials) ─▶ ingest      threatintel :8005 (CISA KEV, OTX, MISP) ─▶ Qdrant, OpenSearch
   enrichment :8082 (IOC reputation, private only) ◀─ fusion, agents            ueba :8004 (baselines from aisoc.raw_events) ─▶ Kafka ueba.anomalies
```

Only **web** and **ingest** have public domains. Everything else is on Railway's private network (`<service>.railway.internal`).

## Security posture

- **Authentication everywhere by default.** Every AiSOC service runs with `ENVIRONMENT=production` and `AISOC_DEV_MODE=0` (upstream's production overlay pins the same literals), so the development auth bypass in `services/api/app/api/v1/dev_auth.py` is unreachable and the API refuses to boot on an insecure default. Upstream's route gate (`scripts/check_route_auth.py`) documents the only unauthenticated routes: health/readiness probes, the sign-in/SSO/MFA/passkey/refresh flow, the waitlist sign-up form (rate-limited, writes only a waitlist row, grants nothing), static catalogue reads (community plugins/detections, compliance framework lists, rule-translation formats), deliberately published replays, the VAPID public key and an ML status boolean.
- **Administrator bootstrap without open setup.** No account exists until the api pre-deploy step runs upstream's `app.scripts.bootstrap_admin` with `AISOC_ADMIN_EMAIL` / `AISOC_ADMIN_PASSWORD` (generated). There is no sign-up page that creates accounts; `/signup` redirects to the dashboard (which requires sign-in). Further users are invited by the admin.
- **Telemetry needs a token.** `POST /v1/ingest` and `/v1/ingest/batch` accept a per-tenant push token minted in the console (or with `python -m app.scripts.mint_ingest_token` in the api shell), or the shared `AISOC_SERVICE_TOKEN` together with an `X-Tenant-ID` header naming an active tenant. `/v1/inbox/*` takes inbox tokens; `/v1/ingest/k8s-audit` stays 503 until `K8S_AUDIT_SHARED_SECRET` is set; the graph WebSocket and OTLP routes are not mounted (their flags are off).
- **Human approval before vendor actions** (upstream design, set explicitly here): `AISOC_MATURITY_TIER=L1` (notify: only read-only impact may run unattended), `AISOC_ACTIONS_REQUIRE_APPROVER=true`, `AISOC_ACTIONS_DEFAULT_DRY_RUN=true`, `AISOC_ALLOW_HIGH_BLAST_AUTO=false`, mailbox remediation off, and the playbook `*_EXECUTE` flags at 0. Isolate host, disable user, reset password, kill process, run script, suspend session, block IOC, sync detection rule, purge email and block sender always require approval in the actions service, whatever the tier.
- **No default credentials.** Every secret is generated with `secret()`; none of upstream's published development literals (`aisoc_dev_secret`, `redis_dev_secret`, `sk-aisoc-local`, …) appears. The LiteLLM master key is generated too (upstream's compose default is a published literal).
- **Data in transit.** Railway's private network is encrypted. The api and ingest additionally require TLS to Postgres (`sslmode=require`; Railway's Postgres serves TLS); the other Python services negotiate it opportunistically (asyncpg's default `prefer`). Kafka runs PLAINTEXT on the private network with upstream's explicit opt-in `AISOC_ALLOW_CLEARTEXT_KAFKA=1`.
- **Closed proxy.** The console's `/api/v1/enrichment/*` rewrite would forward anonymous requests to the enrichment service, which has no authentication and holds the reputation-API keys. No console code calls it, so `ENRICHMENT_URL` on web points at a closed local port; fusion and agents still reach enrichment privately.

## Deviations from upstream (and why)

| # | Change | Why |
|---|---|---|
| 1 | **Redpanda v24.3.18 (Kafka API) replaces cp-kafka 7.5.0 + ZooKeeper.** Listeners on `[::]`, advertised on the private domain, `--mode dev-container` (auto-creates topics, as upstream's `KAFKA_AUTO_CREATE_TOPICS_ENABLE=true`), 7-day retention by default (upstream: 168 h), `--memory 1G`. | One service and one volume instead of two (Railway: one volume per service; upstream needs two ZooKeeper volumes); no JVM; the IPv4+IPv6 listener and start command are the ones deploy-tested in our Huly and PostHog templates. Upstream's own threatintel default broker is `redpanda:9092`. |
| 2 | **Postgres = Railway `postgres-ssl:18`** with owner role/database `aisoc`. The schema (138 SQL files) and the `aisoc_app` runtime role come from upstream's migration runner in the api pre-deploy step, strict mode on. | Railway cannot mount upstream's `initdb` hooks; the runner is upstream's documented path for existing volumes and creates/rotates `aisoc_app` from `AISOC_APP_DB_PASSWORD`. |
| 3 | **Qdrant v1.19.2** instead of v1.7.0. | The services' `qdrant-client` is 1.19.1 (agents) and 1.20.0 (threatintel); Qdrant supports client/server one minor apart. A 1.7 server lacks APIs those clients may call. |
| 4 | **Ollama 0.40.3** with a CPU wrapper instead of 0.6.7 + a one-shot `ollama-pull` container. Threads = CPU quota (max 8), a CPU-tuned model copy `aisoc-llama3.2:3b` (explicit `num_thread`, 8k context), q8_0 KV cache, one request at a time. | Rule 8.15: on Railway's many-core hosts the runner otherwise starts one thread per visible core and generation stalls. The pull runs inside the service (no ordering dependency). |
| 5 | **LiteLLM** config baked into a thin image; master key generated; `AISOC_LITELLM_REQUEST_TIMEOUT=300` (upstream 60). | No bind mounts on Railway; upstream issue #1241 recommends 300 for CPU-only inference. |
| 6 | **ClickHouse** init SQL baked into a thin image; console logging, smaller caches, unused ports and system logs off. | No bind mounts on Railway. |
| 7 | **OpenSearch** started through a root wrapper that fixes volume ownership and drops to uid 1000; `bootstrap.memory_lock=false`, `node.store.allow_mmap=false`, performance-analyzer agent off. | Root-owned Railway volumes; no memlock/vm.max_map_count control on Railway. |
| 8 | **Neo4j** with Neo4j 5 setting names, page cache capped at 256 MB, usage reports off, no `/logs` volume (logs go to stdout). | One volume per service; upstream's 4.x-style names still work but are deprecated. |
| 9 | `full`-profile services included: ClickHouse, OpenSearch, Neo4j, enrichment, ueba; lake writer and graph-at-ingest on. | Production-quality stack (event lake, hunts, entity graph, UEBA), as `make up-full`. |
| 10 | Not included: `kafka-ui` (unauthenticated topic browser; upstream's prod overlay moves it to a debug profile), the `monitoring` profile (Prometheus, Grafana, Tempo, OTel collector, Alertmanager), `chatops` (Slack/Teams bots need workspace apps and tokens), `mcp` (opt-in, no published image), `osquery-tls`, `honeytokens`/`purple-team` (extras), `demo-producer`, `preflight-secrets`. | Optional profiles that need external accounts or are developer tools. `preflight-secrets` exists to refuse published literals; here every secret is generated. Tracing exporters are off (`OTEL_EXPORTER=none`, `OTEL_SDK_DISABLED=true`) because no collector runs. |
| 11 | Every service URL is set explicitly to `<svc>.railway.internal` (about 40 variables). | Upstream defaults such as `http://api:8000`, `http://ingest-worker:8080`, `http://realtime:8086`, `http://aisoc-api:8000` are Compose names that do not resolve on Railway. |
| 12 | `FUSION_SERVICE_URL` set on the api and agents. | Upstream compose leaves the API's authenticated fusion gateway unwired, so entity-risk and ML pages answer empty. |
| 13 | Volumes added for **fusion** (`/data/lake-spool`) and **agents** (`/data/playbooks`). | Fusion's own config says to mount a volume for the lake spool, or rows whose Kafka offsets were committed are lost with the container. Console-created playbooks are written to the agents container's filesystem (`PLAYBOOK_STORE_DIR`); the shipped playbook pack is read from the image as before. |
| 14 | The api pre-deploy waits (≤ 5 min, non-fatal) for Kafka, Neo4j, ClickHouse and Qdrant; ingest waits (≤ 3 min) for Neo4j. | Both disable their graph connection for the life of the process if Neo4j is not up at start; on a first deploy everything starts at once. |
| 15 | `AISOC_MIGRATIONS_STRICT=1`. | A failed migration fails the deploy instead of booting against missing tables. |
| 16 | Healthchecks: `/readyz` on every Python service and ingest, `/api/health` on web, `/healthz` on realtime. | Readiness includes the Kafka subscriptions and lifespan wiring (Rule: readiness endpoint preferred). |
| 17 | Agents download MITRE's public ATT&CK bundle once (`AISOC_ATTCK_CDN_FETCH=1`) and cache it on their volume. | The image ships no bundle, so upstream's default (no egress, for air-gapped installs) leaves the agents on a small built-in technique list. Set `AISOC_ATTCK_CDN_FETCH=0` to restore upstream behaviour. Ingest keeps upstream's behaviour (no bundle, technique enrichment at ingest off; fusion detections are unaffected). |

## Services

| Service | Source | Public | Port | Healthcheck (timeout) | Volume | Restart |
|---|---|---|---|---|---|---|
| web | image `aisoc-web:v20.3.0` | **yes** | 3000 | `/api/health` (600 s) | – | ALWAYS |
| api | image `aisoc-core-api:v20.3.0` + pre-deploy (migrations, admin, waits; 1800 s) | – | 8000 | `/readyz` (900 s) | – | ALWAYS |
| ingest | image `aisoc-ingest:v20.3.0` (start: wait for Neo4j, then `./ingest-service`) | **yes** | 8080 | `/readyz` (900 s) | – | ALWAYS |
| fusion | image `aisoc-fusion:v20.3.0` | – | 8003 | `/readyz` (900 s) | `/data` | ALWAYS |
| agents | image `aisoc-agents:v20.3.0` | – | 8084 | `/readyz` (900 s) | `/data` | ALWAYS |
| actions | image `aisoc-actions:v20.3.0` | – | 8085 | `/readyz` (900 s) | – | ALWAYS |
| connectors | image `aisoc-connectors:v20.3.0` | – | 8003 | `/readyz` (900 s) | – | ALWAYS |
| threatintel | image `aisoc-threatintel:v20.3.0` | – | 8005 | `/readyz` (900 s) | – | ALWAYS |
| realtime | image `aisoc-realtime:v20.3.0` | – | 8086 | `/healthz` (600 s) | – | ALWAYS |
| enrichment | image `aisoc-enrichment:v20.3.0` | – | 8082 | `/health` (600 s) | – | ALWAYS |
| ueba | image `aisoc-ueba:v20.3.0` (own Alembic chain at start) | – | 8004 | `/readyz` (900 s) | – | ALWAYS |
| litellm | repo `baranberkay96/aisoc-railway`, root `/services/litellm` | – | 4000 | `/health/liveliness` (600 s) | – | ALWAYS |
| ollama | repo, root `/services/ollama` | – | 11434 | `/` (900 s) | `/root/.ollama` | ON_FAILURE ×10 |
| kafka | image `redpanda:v24.3.18` (start command below) | – | 9092 (admin 9644) | `/v1/status/ready` (600 s) | `/var/lib/redpanda/data` | ON_FAILURE ×10 |
| qdrant | image `qdrant:v1.19.2` | – | 6333 | `/readyz` (300 s) | `/qdrant/storage` | ON_FAILURE ×10 |
| clickhouse | repo, root `/services/clickhouse` | – | 8123/9000 | `/ping` (600 s) | `/var/lib/clickhouse` | ON_FAILURE ×10 |
| opensearch | repo, root `/services/opensearch` | – | 9200 | `/_cluster/health` (600 s) | `/usr/share/opensearch/data` | ON_FAILURE ×10 |
| neo4j | image `neo4j:5.15.0-community` | – | 7474/7687 | `/` (600 s) | `/data` | ON_FAILURE ×10 |
| Postgres | Railway base `postgres-ssl:18` | – | 5432 | – | `/var/lib/postgresql/data` | ON_FAILURE ×10 |
| Redis | Railway base `redis:8.2.11` | – | 6379 | – | `/data` | ON_FAILURE ×10 |

20 services (Railway limit 25). All replicas = 1. Exact start and pre-deploy commands are in `template.json`; in short:

- **api pre-deploy:** `python -m app.scripts.run_migrations` (up to 5 attempts, 15 s apart, each with the runner's own ~3-minute connect retry) → `python -m app.scripts.bootstrap_admin` (fails the deploy if it fails) → wait for `AISOC_RAILWAY_WAIT_FOR` host:port pairs (bash `/dev/tcp`, 5 minutes in total, never fatal).
- **ingest start:** busybox `wget` against Neo4j's HTTP port, up to 36 × 5 s, then `exec ./ingest-service`.
- **kafka start:** our Huly template's Redpanda command: removes `lost+found`, `rpk redpanda start` with Kafka/Pandaproxy/Schema-Registry listeners on `[::]`, advertised on `$RAILWAY_PRIVATE_DOMAIN`, `--mode dev-container --smp 1 --memory $REDPANDA_MEMORY`.
- **Redis start:** the Railway base command.

### Repo-based services (`baranberkay96/aisoc-railway`)

| Root directory | Contents |
|---|---|
| `/services/clickhouse` | `FROM clickhouse/clickhouse-server:23.8.16.16@sha256:…`, upstream `001_init.sql` in `/docker-entrypoint-initdb.d` (runs once on an empty volume), `config.d/railway.xml`, `railway-entrypoint.sh` (refuses to start without a password or as `default`, removes `lost+found`, `exec /entrypoint.sh`). |
| `/services/opensearch` | `FROM opensearchproject/opensearch:2.11.1@sha256:…`, `USER root`, `railway-start.sh` (chown the data volume to 1000, then `chroot --userspec=1000:1000 /` and `cd /usr/share/opensearch && exec ./opensearch-docker-entrypoint.sh opensearch`). |
| `/services/litellm` | `FROM ghcr.io/berriai/litellm:v1.102.1@sha256:…`, upstream `infra/litellm/config.yaml` at `/etc/litellm/config.yaml`, `CMD --config … --port 4000`. |
| `/services/ollama` | `FROM ollama/ollama:0.40.3@sha256:…`, `railway-entrypoint.sh` (thread sizing → `LLAMA_ARG_THREADS`, `ollama serve`, first-boot pull, tuned model). |

No Dockerfile contains a `VOLUME` instruction (Rule 8.17). The ClickHouse, Neo4j, Redpanda and Redis base images declare their own; image-based and FROM-based use of such images has deployed fine on Railway (PostHog ClickHouse, Huly Redpanda).

## Improvements over market templates

No market template exists. Compared with upstream's own Railway guide (`infra/railway/`, demo profile) and the raw compose files:

| # | This template | Upstream Railway guide / compose |
|---|---|---|
| 1 | Full production pipeline: 20 services incl. Kafka API, fusion, ingest, lake, graph, vectors, UEBA, local LLM | Guide: 4 services in demo mode with Kafka/ClickHouse/Neo4j/Qdrant disabled and seeded demo data |
| 2 | One-click: every service, reference and secret wired | Guide: deploy button for the api only, three services added by hand |
| 3 | No published credential anywhere; admin created with a generated password | Guide: demo auto-login `demo@example.com` / `aisoc-demo`; compose defaults are published literals guarded by a preflight container |
| 4 | Railway-specific fixes: private DNS URLs, IPv4/IPv6 listeners, root-owned volumes, CPU-quota-sized inference, no bind mounts | Compose assumes Docker DNS names, bind mounts and host-sized thread pools |
| 5 | Persistence for the lake spool and console-created playbooks | Container filesystem |
| 6 | Unauthenticated enrichment proxy closed at the console | Open whenever enrichment runs |

## First login

1. Wait until **api** and **web** are healthy. The first deploy builds four small images (ClickHouse, OpenSearch, LiteLLM, Ollama wrappers) and pulls about 8 GB of compressed images (Ollama alone is 3.8 GB); the api pre-deploy then applies the migration chain and creates the administrator. Ollama downloads the 2 GB model in the background after it is healthy.
2. Open the **web** service's public URL and sign in with `AISOC_ADMIN_EMAIL` (default `admin@aisoc.internal`) and `AISOC_ADMIN_PASSWORD` (api → Variables). Change the password in the console.
3. A new tenant lands on the **setup wizard**. Press **Load sample data**: five labelled scenarios (low to critical, source `AiSOC`) go through the real ingest → Kafka → fusion → alert path and appear in Alerts; auto-triage by the local model follows (CPU: expect tens of seconds to minutes per alert). The button refuses to load into a tenant that already has real alerts.
4. **Threat Intelligence** shows the CISA Known Exploited Vulnerabilities catalogue a few minutes after threatintel starts (public feed, no key).
5. Real telemetry: in the wizard, reveal the push URL to mint a per-tenant token and `POST https://{ingest-domain}/v1/ingest` with `Authorization: Bearer {token}`; or add a connector (credentials are encrypted with `AISOC_CREDENTIAL_KEY`). Responses the agents propose appear under Approvals and wait for a human.

Lost the password? In the api service's shell: `python -m app.scripts.bootstrap_admin --reset-password` (sets it to the current `AISOC_ADMIN_PASSWORD`).

## Using a hosted LLM (optional)

- **Per tenant:** console → Settings → Deployment & AI (upstream's BYOK path), or the first-run wizard.
- **Deployment-wide:** on **litellm** set `OPENAI_API_KEY` (or `ANTHROPIC_API_KEY`), `AISOC_LLM_MODEL_FAST` / `AISOC_LLM_MODEL_DEEP` to LiteLLM model strings such as `openai/{model}` or `anthropic/{model}`, and `AISOC_LLM_API_BASE` to an empty value; redeploy litellm, api and agents (they reference the key). You can then delete the **ollama** service to save about $15–30/month.

Upstream's own grading of the bundled 3B model is close to chance on its verdict corpus; it proves the pipeline end to end but a hosted model is recommended for real triage. Either way, actions stay behind human approval.

## Scaling

- **Stateless, can take replicas:** web, api (background schedulers are lock-guarded), ingest, actions, enrichment.
- **Keep at 1 replica:** fusion and agents (volumes; raise memory instead), connectors (one poll leader), threatintel (feed scheduler), ueba, realtime.
- Kafka topics are auto-created with one partition, which caps consumer parallelism; create topics with more partitions (`rpk topic create … -p N` in the kafka shell) before scaling consumers.
- Raise memory with: `REDPANDA_MEMORY` (kafka), `OPENSEARCH_JAVA_OPTS` (heap ≈ half of the service RAM), the Neo4j heap/page-cache variables, ClickHouse uses up to 80% of its RAM.
- Larger local model: set `OLLAMA_PULL_MODELS` / `OLLAMA_BASE_MODEL` (upstream's measurement favours `llama3.1:8b-instruct-q4_K_M`) and give ollama 8 GB+ RAM and more vCPU.

## Resource estimate

Railway prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month. Figures marked † are upstream's own measurements (compose comments); the rest are estimates, not measured on Railway.

| Service | Idle RAM | Typical RAM | Typical CPU |
|---|---|---|---|
| web | 150 MB | 300 MB | 0.05 |
| api | 400 MB | 700 MB | 0.15 |
| ingest | 30 MB | 100 MB | 0.05 |
| fusion | 250 MB | 500 MB | 0.2 |
| agents | 350 MB | 700 MB | 0.1 |
| actions | 50 MB † | 100 MB | 0.01 |
| connectors | 80 MB † | 200 MB | 0.05 |
| threatintel | 220 MB † | 300 MB | 0.05 |
| realtime | 60 MB | 120 MB | 0.02 |
| enrichment | 20 MB | 50 MB | 0.01 |
| ueba | 150 MB | 300 MB | 0.05 |
| litellm | 450 MB † | 500 MB | 0.02 |
| ollama (model unloaded / loaded) | 50 MB | 1.5 GB average, 3 GB † while loaded | 1.0 (4–8 vCPU bursts while generating) |
| kafka (Redpanda) | 250 MB | 500 MB | 0.1 |
| qdrant | 80 MB † | 200 MB | 0.02 |
| clickhouse | 300 MB | 1.0 GB | 0.15 |
| opensearch | 1.05 GB † | 1.3 GB | 0.1 |
| neo4j | 800 MB | 1.0 GB | 0.05 |
| Postgres | 60 MB | 300 MB | 0.1 |
| Redis | 10 MB | 100 MB | 0.02 |
| **Total** | **≈ 4.8 GB** (≈ 0.4 vCPU) | **≈ 9.8 GB** | **≈ 2.3 vCPU** |

- **Idle:** ≈ $48 RAM + $8 CPU + $1 volumes (≈ 7 GB) ≈ **$57/month**.
- **Typical** (small SOC, a few connectors, local model triaging): ≈ $98 RAM + $46 CPU + $3 volumes (≈ 20 GB) ≈ **$150/month**.
- **Hosted LLM instead of ollama:** about $15–30/month less on Railway, plus the provider's bill.
- **Minimum plan: Hobby** (OpenSearch, Neo4j and Ollama each need more than Trial's 1 GB). **Pro recommended** for real telemetry: Hobby's 5 GB volume limit per service is reached quickly by ClickHouse and OpenSearch.

## Variables (all services)

Generated from `template.json`. `${{svc.VAR}}` references resolve on Railway; `${{secret(n, "alphabet")}}` is generated once at deploy.

#### web

| Variable | Value | Description |
|---|---|---|
| `PORT` | `3000` | Port the Next.js console listens on (the image starts it with -p 3000); Railway routes the public domain and its healthcheck here. |
| `NODE_ENV` | `production` | Next.js production mode. |
| `AISOC_DEMO_MODE` | `false` | Demo mode off: the console never shows seeded demo data or the demo banner. Keep false. |
| `API_URL` | `http://${{api.RAILWAY_PRIVATE_DOMAIN}}:8000` | Core API on the private network. The console proxies /api/v1/* and /auth/* here server-side, so the API needs no public domain. |
| `AGENTS_URL` | `http://${{agents.RAILWAY_PRIVATE_DOMAIN}}:8084` | Agents service on the private network (copilot, hunts, playbooks routes). |
| `REALTIME_URL` | `http://${{realtime.RAILWAY_PRIVATE_DOMAIN}}:8086` | Realtime gateway on the private network (WebSocket /ws and SSE /sse are proxied here). |
| `ENRICHMENT_URL` | `http://127.0.0.1:9` | Deliberately unreachable. The console has no caller of /api/v1/enrichment/*, and that rewrite would otherwise expose the unauthenticated enrichment service through the public console. |

#### api

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8000` | Port the API listens on (dual-stack); Railway's healthcheck probes it. |
| `ENVIRONMENT` | `production` | Production posture: the development auth bypass is unreachable and insecure defaults refuse to boot. Do not change. |
| `AISOC_DEV_MODE` | `0` | Development mode off: routes never fall back to an anonymous or demo principal. Do not change. |
| `AISOC_PUBLISHED_BIND_ADDRS` | `0.0.0.0` | Tells the service it is reachable from other hosts, so the developer auth shim stays refused even if dev mode were switched on. |
| `AISOC_ALLOW_CLEARTEXT_KAFKA` | `1` | Allow PLAINTEXT Kafka in production: the broker is reachable only over Railway's private network, which Railway encrypts. Set KAFKA_SECURITY_PROTOCOL instead if you bring a TLS broker. |
| `AISOC_ADMIN_EMAIL` | `admin@aisoc.internal` | Sign-in e-mail of the first administrator, created by the pre-deploy step on the first deploy. Change it before deploying if you like (must be a syntactically valid address; .local/.test are rejected). |
| `AISOC_ADMIN_PASSWORD` | `${{secret(24, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Password of the first administrator (generated, 24 characters). Copy it from here to sign in; changing this variable later does not change an existing account (reset with `python -m app.scripts.bootstrap_admin --reset-password` in the api service shell). |
| `SECRET_KEY` | `${{secret(64, "0123456789abcdef")}}` | HS256 key for console sessions, shared by every service that verifies a console token (generated). |
| `JWT_SECRET` | `${{secret(48, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | HS256 key for SAML/OIDC session tokens, shared with ingest (generated; required in production). |
| `AISOC_CREDENTIAL_KEY` | `${{secret(42, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")}}${{secret(1, "AEIMQUYcgkosw048")}}=` | Fernet key (32 bytes, url-safe base64) that encrypts connector credentials at rest; shared with connectors and actions (generated). Never change it after connectors are saved; rotate with AISOC_CREDENTIAL_KEY_ROTATION_FROM. |
| `AISOC_SERVICE_TOKEN` | `${{secret(48, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Shared bearer for service-to-service calls and connector pushes to ingest (generated). |
| `AISOC_API_SERVICE_TOKEN` | `${{secret(48, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Bearer a peer service presents to the API (agent customer tools, lake pivots, hunts) (generated). |
| `AISOC_AGENTS_SERVICE_TOKEN` | `${{secret(48, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Bearer between the API and the agents service (triage context, MCP tools, SIEM writeback) (generated). |
| `AISOC_ACTIONS_SERVICE_TOKEN` | `${{secret(48, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Bearer that gates every response action on the actions service (generated). Kept separate from the shared token on purpose. |
| `AISOC_REALTIME_JWT_SECRET` | `${{secret(48, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | HS256 key for realtime WebSocket/SSE tickets; the API mints, realtime verifies (generated). |
| `REALTIME_INTERNAL_TOKEN` | `${{secret(48, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Bearer for realtime's /internal/* fan-out routes (generated). |
| `METRICS_TOKEN` | `${{secret(48, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Bearer required on /metrics outside development (generated). |
| `AISOC_APP_DB_PASSWORD` | `${{secret(48, "0123456789abcdef")}}` | Password of the aisoc_app runtime database role (DML only, row-level security applies). The pre-deploy migration step creates the role and sets this password (generated). |
| `DATABASE_URL` | `postgresql+asyncpg://aisoc_app:${{AISOC_APP_DB_PASSWORD}}@${{Postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/${{Postgres.POSTGRES_DB}}?sslmode=require` | Runtime connection as aisoc_app, TLS required (Railway Postgres serves TLS). |
| `DATABASE_MIGRATION_URL` | `postgresql+asyncpg://${{Postgres.POSTGRES_USER}}:${{Postgres.POSTGRES_PASSWORD}}@${{Postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/${{Postgres.POSTGRES_DB}}?sslmode=require` | Owner connection used only by the pre-deploy migration runner for DDL, TLS required. |
| `AISOC_MIGRATIONS_STRICT` | `1` | Fail the deploy if any SQL migration fails, instead of booting on a partial schema. |
| `REDIS_URL` | `redis://default:${{Redis.REDIS_PASSWORD}}@${{Redis.RAILWAY_PRIVATE_DOMAIN}}:6379/0` | Redis (database 0) on the private network. |
| `KAFKA_BOOTSTRAP_SERVERS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka-API broker (Redpanda) on the private network. |
| `CLICKHOUSE_HOST` | `${{clickhouse.RAILWAY_PRIVATE_DOMAIN}}` | ClickHouse event lake host (native protocol). |
| `CLICKHOUSE_PORT` | `9000` | ClickHouse native port. |
| `CLICKHOUSE_DATABASE` | `aisoc` | ClickHouse database. |
| `CLICKHOUSE_USER` | `${{clickhouse.CLICKHOUSE_USER}}` | ClickHouse user. |
| `CLICKHOUSE_PASSWORD` | `${{clickhouse.CLICKHOUSE_PASSWORD}}` | ClickHouse password. |
| `QDRANT_URL` | `http://${{qdrant.RAILWAY_PRIVATE_DOMAIN}}:6333` | Qdrant vector store. |
| `NEO4J_URI` | `bolt://${{neo4j.RAILWAY_PRIVATE_DOMAIN}}:7687` | Neo4j entity graph (direct Bolt). |
| `NEO4J_USER` | `neo4j` | Neo4j user. |
| `NEO4J_PASSWORD` | `${{neo4j.AISOC_NEO4J_PASSWORD}}` | Neo4j password. |
| `CONNECTORS_SERVICE_URL` | `http://${{connectors.RAILWAY_PRIVATE_DOMAIN}}:8003` | Connectors service (catalog, test connection, federated search). |
| `THREATINTEL_SERVICE_URL` | `http://${{threatintel.RAILWAY_PRIVATE_DOMAIN}}:8005` | Threat-intel service (serves /api/v1/threat-intel/indicators). |
| `AGENTS_SERVICE_URL` | `http://${{agents.RAILWAY_PRIVATE_DOMAIN}}:8084` | Agents service (investigations, playbooks). |
| `FUSION_SERVICE_URL` | `http://${{fusion.RAILWAY_PRIVATE_DOMAIN}}:8003` | Fusion service behind the API's authenticated fusion gateway (entity risk, ML status). |
| `REALTIME_BASE_URL` | `http://${{realtime.RAILWAY_PRIVATE_DOMAIN}}:8086` | Realtime gateway for /internal/* fan-out. |
| `AISOC_ACTIONS_BASE_URL` | `http://${{actions.RAILWAY_PRIVATE_DOMAIN}}:8085` | Actions service, where an approved response action is executed. |
| `INGEST_SERVICE_URL` | `http://${{ingest.RAILWAY_PRIVATE_DOMAIN}}:8080` | Ingest service on the private network. |
| `INGEST_PUBLIC_URL` | `https://${{ingest.RAILWAY_PUBLIC_DOMAIN}}` | Public ingest URL shown in the setup wizard's push-URL examples. The sample-data button also posts here. Update after adding a custom domain to ingest. |
| `LLM_GATEWAY_URL` | `http://${{litellm.RAILWAY_PRIVATE_DOMAIN}}:4000/v1` | LiteLLM gateway that resolves every aisoc-* model alias. |
| `LITELLM_MASTER_KEY` | `${{litellm.LITELLM_MASTER_KEY}}` | Bearer the API presents to the LiteLLM gateway. |
| `OPENAI_API_KEY` | `${{litellm.OPENAI_API_KEY}}` | Optional hosted-provider key (empty = local model only). Set it on the litellm service; this references it. |
| `AISOC_OLLAMA_URL` | `http://${{ollama.RAILWAY_PRIVATE_DOMAIN}}:11434` | Local Ollama server, probed by the console's 'Deployment & AI' page. |
| `AISOC_CONSOLE_URL` | `https://${{web.RAILWAY_PUBLIC_DOMAIN}}` | Console origin printed by the admin bootstrap and used in links. |
| `CONSOLE_PUBLIC_BASE_URL` | `https://${{web.RAILWAY_PUBLIC_DOMAIN}}` | Console origin for share/invite links and OAuth return URLs. Update after adding a custom domain to web. |
| `OAUTH_PUBLIC_BASE_URL` | `https://${{web.RAILWAY_PUBLIC_DOMAIN}}` | Base URL advertised as the OAuth redirect for connector sign-in (the console proxies /api/v1/oauth/callback to the API). |
| `AISOC_CORS_ORIGINS` | `https://${{web.RAILWAY_PUBLIC_DOMAIN}}` | Allowed browser origin (the console). |
| `PASSKEY_RP_ID` | `${{web.RAILWAY_PUBLIC_DOMAIN}}` | WebAuthn relying-party id: the console host name. Update after adding a custom domain. |
| `PASSKEY_RP_ORIGINS` | `["https://${{web.RAILWAY_PUBLIC_DOMAIN}}"]` | WebAuthn origins as a JSON list (the console origin). |
| `RETRO_HUNT_ENABLED` | `false` | Retro-hunt sweeps over stored history (cost and privacy decision; off as upstream). |
| `OTEL_EXPORTER` | `none` | Tracing exporter off (no OpenTelemetry collector in this template). |
| `LOG_LEVEL` | `info` | Log level. |
| `AISOC_RAILWAY_WAIT_FOR` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092 ${{neo4j.RAILWAY_PRIVATE_DOMAIN}}:7687 ${{clickhouse.RAILWAY_PRIVATE_DOMAIN}}:9000 ${{qdrant.RAILWAY_PRIVATE_DOMAIN}}:6333` | Template helper: the pre-deploy step waits (up to 5 minutes in total, non-fatal) until these host:port pairs accept connections, so the API starts with its graph and lake connections available on a first deploy. |

#### ingest

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8080` | Port Railway routes the public domain and healthcheck to (same as HTTP_PORT). |
| `HTTP_PORT` | `8080` | Ingest HTTP port. |
| `METRICS_PORT` | `9090` | Separate metrics listener port (private). |
| `ENV` | `production` | Read before ENVIRONMENT by ingest's mode check. Production requires JWT_SECRET and disables development shortcuts. Do not change. |
| `ENVIRONMENT` | `production` | Production posture. Do not change. |
| `AISOC_ALLOW_CLEARTEXT_KAFKA` | `1` | Allow PLAINTEXT Kafka on Railway's encrypted private network. |
| `KAFKA_BOOTSTRAP_SERVERS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka-API broker (Redpanda). |
| `DATABASE_DSN` | `postgres://aisoc_app:${{api.AISOC_APP_DB_PASSWORD}}@${{Postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/${{Postgres.POSTGRES_DB}}?sslmode=require` | Postgres (pgx DSN, TLS required) used to resolve minted push tokens and mount the /v1/inbox/* webhook routes. |
| `JWT_SECRET` | `${{api.JWT_SECRET}}` | Same JWT secret as the API (ingest refuses to start without one in production). |
| `AISOC_SERVICE_TOKEN` | `${{api.AISOC_SERVICE_TOKEN}}` | Shared service token; accepted on /v1/ingest only together with an X-Tenant-ID header naming an active tenant. |
| `ATTCK_DATA_PATH` | `/app/data/enterprise-attack.json` | Upstream's path for the ATT&CK bundle. The published image does not contain it, so technique enrichment at ingest is off (upstream behaviour, logged as a warning); detections and the agents still map techniques. |
| `AISOC_GRAPH_ENABLED` | `true` | Write entities to the Neo4j graph at ingest (upstream 'full' profile). |
| `AISOC_NEO4J_URI` | `bolt://${{neo4j.RAILWAY_PRIVATE_DOMAIN}}:7687` | Neo4j entity graph. |
| `AISOC_NEO4J_USER` | `neo4j` | Neo4j user. |
| `AISOC_NEO4J_PASSWORD` | `${{neo4j.AISOC_NEO4J_PASSWORD}}` | Neo4j password. |
| `AISOC_CORS_ORIGINS` | `https://${{web.RAILWAY_PUBLIC_DOMAIN}}` | Allowed browser origin (the console). Telemetry senders are not browsers and are unaffected. |
| `AISOC_RAILWAY_WAIT_URL` | `http://${{neo4j.RAILWAY_PRIVATE_DOMAIN}}:7474/` | Template helper: ingest waits up to 3 minutes for Neo4j at start, because its graph writer disables itself for the life of the process if Neo4j is not reachable within 60 s. |

#### fusion

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8003` | Port fusion listens on (fixed in the image's command); Railway's healthcheck probes it. |
| `ENVIRONMENT` | `production` | Production posture: the development auth bypass is unreachable and insecure defaults refuse to boot. Do not change. |
| `AISOC_DEV_MODE` | `0` | Development mode off: routes never fall back to an anonymous or demo principal. Do not change. |
| `AISOC_PUBLISHED_BIND_ADDRS` | `0.0.0.0` | Tells the service it is reachable from other hosts, so the developer auth shim stays refused even if dev mode were switched on. |
| `AISOC_ALLOW_CLEARTEXT_KAFKA` | `1` | Allow PLAINTEXT Kafka in production: the broker is reachable only over Railway's private network, which Railway encrypts. Set KAFKA_SECURITY_PROTOCOL instead if you bring a TLS broker. |
| `SECRET_KEY` | `${{api.SECRET_KEY}}` | Console token key (verifies console callers). |
| `AISOC_SERVICE_TOKEN` | `${{api.AISOC_SERVICE_TOKEN}}` | Shared service token. |
| `DATABASE_URL` | `postgresql+asyncpg://aisoc_app:${{api.AISOC_APP_DB_PASSWORD}}@${{Postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/${{Postgres.POSTGRES_DB}}` | Postgres as aisoc_app (alerts, outbox). |
| `REDIS_URL` | `redis://default:${{Redis.REDIS_PASSWORD}}@${{Redis.RAILWAY_PRIVATE_DOMAIN}}:6379/3` | Redis (database 3). |
| `KAFKA_BOOTSTRAP_SERVERS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka-API broker (Redpanda). |
| `AISOC_LAKE_WRITER_ENABLED` | `true` | Archive every event to the ClickHouse lake (upstream 'full' profile). |
| `AISOC_LAKE_SPOOL_DIR` | `/data/lake-spool` | On-disk spool for lake rows not yet written (on the volume, so committed Kafka offsets are never lost on redeploy). |
| `CLICKHOUSE_HOST` | `${{clickhouse.RAILWAY_PRIVATE_DOMAIN}}` | ClickHouse host. |
| `CLICKHOUSE_PORT` | `9000` | ClickHouse native port. |
| `CLICKHOUSE_DATABASE` | `aisoc` | ClickHouse database. |
| `CLICKHOUSE_USER` | `${{clickhouse.CLICKHOUSE_USER}}` | ClickHouse user. |
| `CLICKHOUSE_PASSWORD` | `${{clickhouse.CLICKHOUSE_PASSWORD}}` | ClickHouse password. |
| `ENRICHMENT_SERVICE_URL` | `http://${{enrichment.RAILWAY_PRIVATE_DOMAIN}}:8082` | Enrichment service for fuse-time IOC enrichment. |

#### agents

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8084` | Port the agents service listens on (dual-stack). |
| `ENVIRONMENT` | `production` | Production posture: the development auth bypass is unreachable and insecure defaults refuse to boot. Do not change. |
| `AISOC_DEV_MODE` | `0` | Development mode off: routes never fall back to an anonymous or demo principal. Do not change. |
| `AISOC_PUBLISHED_BIND_ADDRS` | `0.0.0.0` | Tells the service it is reachable from other hosts, so the developer auth shim stays refused even if dev mode were switched on. |
| `AISOC_ALLOW_CLEARTEXT_KAFKA` | `1` | Allow PLAINTEXT Kafka in production: the broker is reachable only over Railway's private network, which Railway encrypts. Set KAFKA_SECURITY_PROTOCOL instead if you bring a TLS broker. |
| `SECRET_KEY` | `${{api.SECRET_KEY}}` | Console token key. |
| `AISOC_SERVICE_TOKEN` | `${{api.AISOC_SERVICE_TOKEN}}` | Shared service token. |
| `AISOC_API_SERVICE_TOKEN` | `${{api.AISOC_API_SERVICE_TOKEN}}` | Bearer presented to the API. |
| `AISOC_AGENTS_SERVICE_TOKEN` | `${{api.AISOC_AGENTS_SERVICE_TOKEN}}` | This service's own credential (both directions with the API). |
| `AISOC_ACTIONS_SERVICE_TOKEN` | `${{api.AISOC_ACTIONS_SERVICE_TOKEN}}` | Bearer for the actions service (submits proposals; execution still needs approval). |
| `REALTIME_INTERNAL_TOKEN` | `${{api.REALTIME_INTERNAL_TOKEN}}` | Bearer for realtime's /internal/* (playbook progress). |
| `METRICS_TOKEN` | `${{api.METRICS_TOKEN}}` | Bearer required on this service's /metrics. |
| `DATABASE_URL` | `postgresql+asyncpg://aisoc_app:${{api.AISOC_APP_DB_PASSWORD}}@${{Postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/${{Postgres.POSTGRES_DB}}` | Postgres as aisoc_app. |
| `REDIS_URL` | `redis://default:${{Redis.REDIS_PASSWORD}}@${{Redis.RAILWAY_PRIVATE_DOMAIN}}:6379/4` | Redis (database 4). |
| `KAFKA_BOOTSTRAP_SERVERS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka-API broker (auto-triage consumes aisoc.alerts.fused). |
| `KAFKA_TOPIC_ALERTS_FUSED` | `aisoc.alerts.fused` | Topic of fused alerts to triage. |
| `CORE_API_URL` | `http://${{api.RAILWAY_PRIVATE_DOMAIN}}:8000` | Core API. |
| `API_SERVICE_URL` | `http://${{api.RAILWAY_PRIVATE_DOMAIN}}:8000` | Core API (name read by the context and tool modules). |
| `API_URL` | `http://${{api.RAILWAY_PRIVATE_DOMAIN}}:8000` | Core API (name read by the playbook engine). |
| `AISOC_API_URL` | `http://${{api.RAILWAY_PRIVATE_DOMAIN}}:8000` | Core API (name read by hunts, MCP registry and customer tools). |
| `REALTIME_URL` | `http://${{realtime.RAILWAY_PRIVATE_DOMAIN}}:8086` | Realtime gateway. |
| `CONNECTORS_SERVICE_URL` | `http://${{connectors.RAILWAY_PRIVATE_DOMAIN}}:8003` | Connectors service. |
| `FUSION_SERVICE_URL` | `http://${{fusion.RAILWAY_PRIVATE_DOMAIN}}:8003` | Fusion service. |
| `ENRICHMENT_SERVICE_URL` | `http://${{enrichment.RAILWAY_PRIVATE_DOMAIN}}:8082` | Enrichment service. |
| `AISOC_THREATINTEL_URL` | `http://${{threatintel.RAILWAY_PRIVATE_DOMAIN}}:8005` | Threat-intel service. |
| `AISOC_UEBA_URL` | `http://${{ueba.RAILWAY_PRIVATE_DOMAIN}}:8004` | UEBA service. |
| `QDRANT_URL` | `http://${{qdrant.RAILWAY_PRIVATE_DOMAIN}}:6333` | Qdrant vector store. |
| `NEO4J_URI` | `bolt://${{neo4j.RAILWAY_PRIVATE_DOMAIN}}:7687` | Neo4j entity graph. |
| `NEO4J_USER` | `neo4j` | Neo4j user. |
| `NEO4J_PASSWORD` | `${{neo4j.AISOC_NEO4J_PASSWORD}}` | Neo4j password. |
| `CLICKHOUSE_HOST` | `${{clickhouse.RAILWAY_PRIVATE_DOMAIN}}` | ClickHouse host (hunting agent). |
| `CLICKHOUSE_PORT` | `9000` | ClickHouse native port. |
| `CLICKHOUSE_DATABASE` | `aisoc` | ClickHouse database. |
| `CLICKHOUSE_USER` | `${{clickhouse.CLICKHOUSE_USER}}` | ClickHouse user. |
| `CLICKHOUSE_PASSWORD` | `${{clickhouse.CLICKHOUSE_PASSWORD}}` | ClickHouse password. |
| `LLM_GATEWAY_URL` | `http://${{litellm.RAILWAY_PRIVATE_DOMAIN}}:4000/v1` | LiteLLM gateway for every aisoc-* model alias. |
| `LITELLM_MASTER_KEY` | `${{litellm.LITELLM_MASTER_KEY}}` | Bearer for the LiteLLM gateway. |
| `OPENAI_MODEL` | `aisoc-summary` | Model alias for the 'explain this alert' path (resolved by the gateway). |
| `OPENAI_API_KEY` | `${{litellm.OPENAI_API_KEY}}` | Optional hosted-provider key; set on the litellm service. |
| `ANTHROPIC_API_KEY` | `${{litellm.ANTHROPIC_API_KEY}}` | Optional hosted-provider key; set on the litellm service. |
| `ATTCK_DATA_PATH` | `/data/attack/enterprise-attack.json` | Where the full MITRE ATT&CK bundle is cached (on the volume). The image does not ship it. |
| `AISOC_ATTCK_CDN_FETCH` | `1` | Download the public MITRE ATT&CK bundle from MITRE's GitHub once and cache it at ATTCK_DATA_PATH (upstream default is off, for air-gapped installs; without it the agents use a small built-in technique list). Set 0 to keep the service from fetching it. |
| `AISOC_INVESTIGATION_MAX_SECONDS` | `120` | Wall-clock budget of one investigation (upstream default). |
| `CONSOLE_PUBLIC_BASE_URL` | `https://${{web.RAILWAY_PUBLIC_DOMAIN}}` | Console origin for links. |
| `PLAYBOOK_STORE_DIR` | `/data/playbooks` | Where playbooks created in the console are saved (on the volume; upstream writes them into the container). The service creates the directory. |
| `AISOC_PLAYBOOK_ACTIONS_EXECUTE` | `0` | Playbook action steps submit to the actions service as previews only (upstream default). Approval rules still apply when enabled. |
| `AISOC_PLAYBOOK_HTTP_EXECUTE` | `0` | Playbook HTTP steps are previewed, not sent (upstream default). |
| `AISOC_PLAYBOOK_NOTIFY_EXECUTE` | `0` | Playbook notify steps are previewed, not sent (upstream default). |
| `AISOC_PLAYBOOK_VERIFY_EXECUTE` | `0` | Playbook user-verification prompts are previewed, not sent (upstream default). |
| `OTEL_EXPORTER` | `none` | Tracing exporter off (no OpenTelemetry collector in this template). |

#### actions

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8085` | Port the actions service listens on (fixed in the image's command). |
| `ENVIRONMENT` | `production` | Production posture: the development auth bypass is unreachable and insecure defaults refuse to boot. Do not change. |
| `AISOC_DEV_MODE` | `0` | Development mode off: routes never fall back to an anonymous or demo principal. Do not change. |
| `AISOC_PUBLISHED_BIND_ADDRS` | `0.0.0.0` | Tells the service it is reachable from other hosts, so the developer auth shim stays refused even if dev mode were switched on. |
| `AISOC_ALLOW_CLEARTEXT_KAFKA` | `1` | Allow PLAINTEXT Kafka in production: the broker is reachable only over Railway's private network, which Railway encrypts. Set KAFKA_SECURITY_PROTOCOL instead if you bring a TLS broker. |
| `AISOC_ACTIONS_SERVICE_TOKEN` | `${{api.AISOC_ACTIONS_SERVICE_TOKEN}}` | Bearer required on POST /actions and approve/reject; without it every mutating route answers 503. |
| `AISOC_SERVICE_TOKEN` | `${{api.AISOC_SERVICE_TOKEN}}` | Shared service token. |
| `SECRET_KEY` | `${{api.SECRET_KEY}}` | Console token key. |
| `AISOC_CREDENTIAL_KEY` | `${{api.AISOC_CREDENTIAL_KEY}}` | Decrypts vault-encrypted connector credentials in action payloads. |
| `DATABASE_URL` | `postgresql+asyncpg://aisoc_app:${{api.AISOC_APP_DB_PASSWORD}}@${{Postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/${{Postgres.POSTGRES_DB}}` | Postgres as aisoc_app (action records). |
| `REDIS_URL` | `redis://default:${{Redis.REDIS_PASSWORD}}@${{Redis.RAILWAY_PRIVATE_DOMAIN}}:6379/5` | Redis (database 5). |
| `KAFKA_BOOTSTRAP_SERVERS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka-API broker. |
| `CORE_API_URL` | `http://${{api.RAILWAY_PRIVATE_DOMAIN}}:8000` | Core API. |
| `AISOC_API_BASE_URL` | `http://${{api.RAILWAY_PRIVATE_DOMAIN}}:8000` | Core API (name read by the actions settings). |
| `AISOC_MATURITY_TIER` | `L1` | Autonomy tier L1-Notify (upstream default, set explicitly): anything above read-only impact waits for a human approval. |
| `AISOC_ACTIONS_REQUIRE_APPROVER` | `true` | Approve/reject calls must carry a resolvable approver identity (separation of duties). |
| `AISOC_ACTIONS_DEFAULT_DRY_RUN` | `true` | Dry-run by default unless an operator opts out (upstream default, set explicitly). |
| `AISOC_ALLOW_HIGH_BLAST_AUTO` | `false` | Break-glass for unattended high-blast-radius actions. Keep false. |
| `AISOC_FEATURE_MAILBOX_REMEDIATION` | `false` | Mailbox purge/restore/block verbs off (upstream default). |

#### connectors

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8003` | Port the connectors service listens on (dual-stack); the API's connectors URL points here. |
| `ENVIRONMENT` | `production` | Production posture: the development auth bypass is unreachable and insecure defaults refuse to boot. Do not change. |
| `AISOC_DEV_MODE` | `0` | Development mode off: routes never fall back to an anonymous or demo principal. Do not change. |
| `AISOC_PUBLISHED_BIND_ADDRS` | `0.0.0.0` | Tells the service it is reachable from other hosts, so the developer auth shim stays refused even if dev mode were switched on. |
| `AISOC_ALLOW_CLEARTEXT_KAFKA` | `1` | Allow PLAINTEXT Kafka in production: the broker is reachable only over Railway's private network, which Railway encrypts. Set KAFKA_SECURITY_PROTOCOL instead if you bring a TLS broker. |
| `SECRET_KEY` | `${{api.SECRET_KEY}}` | Console token key (the API forwards console tokens here). |
| `AISOC_SERVICE_TOKEN` | `${{api.AISOC_SERVICE_TOKEN}}` | Shared service token (also used to push polled events to ingest). |
| `AISOC_CREDENTIAL_KEY` | `${{api.AISOC_CREDENTIAL_KEY}}` | Decrypts stored connector credentials at poll time (the scheduler refuses to start without it). |
| `DATABASE_URL` | `postgresql+asyncpg://aisoc_app:${{api.AISOC_APP_DB_PASSWORD}}@${{Postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/${{Postgres.POSTGRES_DB}}` | Postgres as aisoc_app. |
| `REDIS_URL` | `redis://default:${{Redis.REDIS_PASSWORD}}@${{Redis.RAILWAY_PRIVATE_DOMAIN}}:6379/6` | Redis (database 6). |
| `KAFKA_BOOTSTRAP_SERVERS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka-API broker. |
| `CORE_API_URL` | `http://${{api.RAILWAY_PRIVATE_DOMAIN}}:8000` | Core API. |
| `INGEST_SERVICE_URL` | `http://${{ingest.RAILWAY_PRIVATE_DOMAIN}}:8080` | Ingest service on the private network (polled events are pushed here). |

#### threatintel

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8005` | Port the threat-intel service listens on (fixed in the image's command). |
| `ENVIRONMENT` | `production` | Production posture: the development auth bypass is unreachable and insecure defaults refuse to boot. Do not change. |
| `AISOC_DEV_MODE` | `0` | Development mode off: routes never fall back to an anonymous or demo principal. Do not change. |
| `AISOC_PUBLISHED_BIND_ADDRS` | `0.0.0.0` | Tells the service it is reachable from other hosts, so the developer auth shim stays refused even if dev mode were switched on. |
| `AISOC_ALLOW_CLEARTEXT_KAFKA` | `1` | Allow PLAINTEXT Kafka in production: the broker is reachable only over Railway's private network, which Railway encrypts. Set KAFKA_SECURITY_PROTOCOL instead if you bring a TLS broker. |
| `SECRET_KEY` | `${{api.SECRET_KEY}}` | Console token key. |
| `AISOC_SERVICE_TOKEN` | `${{api.AISOC_SERVICE_TOKEN}}` | Shared service token (the API presents it when it proxies indicators). |
| `REDIS_URL` | `redis://default:${{Redis.REDIS_PASSWORD}}@${{Redis.RAILWAY_PRIVATE_DOMAIN}}:6379/7` | Redis (database 7). |
| `KAFKA_BOOTSTRAP_SERVERS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka-API broker. |
| `QDRANT_HOST` | `${{qdrant.RAILWAY_PRIVATE_DOMAIN}}` | Qdrant host (this service reads host and port, not a URL). |
| `QDRANT_PORT` | `6333` | Qdrant HTTP port. |
| `OPENSEARCH_HOST` | `${{opensearch.RAILWAY_PRIVATE_DOMAIN}}` | OpenSearch host (IOC and actor full-text index). |
| `OPENSEARCH_PORT` | `9200` | OpenSearch HTTP port. |
| `NEO4J_URI` | `bolt://${{neo4j.RAILWAY_PRIVATE_DOMAIN}}:7687` | Neo4j entity graph. |
| `NEO4J_USER` | `neo4j` | Neo4j user. |
| `NEO4J_PASSWORD` | `${{neo4j.AISOC_NEO4J_PASSWORD}}` | Neo4j password. |
| `OTX_API_KEY` | (empty) | Optional: AlienVault OTX key for an additional indicator feed. The CISA KEV feed needs no key. |
| `MISP_URL` | (empty) | Optional: MISP base URL to pull indicators from. |
| `MISP_API_KEY` | (empty) | Optional: MISP API key. |

#### realtime

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8086` | Port the realtime gateway listens on (dual-stack). |
| `ENVIRONMENT` | `production` | Production posture (refuses a wildcard CORS origin). Do not change. |
| `AISOC_ALLOW_CLEARTEXT_KAFKA` | `1` | Allow PLAINTEXT Kafka on Railway's encrypted private network. |
| `AISOC_REALTIME_JWT_SECRET` | `${{api.AISOC_REALTIME_JWT_SECRET}}` | Verifies realtime tickets minted by the API; unset rejects every connection. |
| `REALTIME_INTERNAL_TOKEN` | `${{api.REALTIME_INTERNAL_TOKEN}}` | Guards /internal/*; unset answers 503. |
| `REDIS_URL` | `redis://default:${{Redis.REDIS_PASSWORD}}@${{Redis.RAILWAY_PRIVATE_DOMAIN}}:6379` | Redis (fan-out). |
| `REDIS_PASSWORD` | `${{Redis.REDIS_PASSWORD}}` | Redis password. |
| `KAFKA_BOOTSTRAP_SERVERS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka-API broker (fused alerts, graph updates). |
| `AISOC_CORS_ORIGINS` | `https://${{web.RAILWAY_PUBLIC_DOMAIN}}` | Allowed browser origin (the console). |

#### enrichment

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8082` | Port Railway's healthcheck probes (same as HTTP_PORT). |
| `HTTP_PORT` | `8082` | Enrichment HTTP port (private only; this service has no authentication of its own). |
| `REDIS_URL` | `redis://default:${{Redis.REDIS_PASSWORD}}@${{Redis.RAILWAY_PRIVATE_DOMAIN}}:6379/2` | Redis (database 2) for the enrichment cache. |
| `KAFKA_BOOTSTRAP_SERVERS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka-API broker. |
| `VIRUSTOTAL_API_KEY` | (empty) | Optional: VirusTotal key for IOC enrichment. |
| `ABUSEIPDB_API_KEY` | (empty) | Optional: AbuseIPDB key for IP reputation. |
| `GREYNOISE_API_KEY` | (empty) | Optional: GreyNoise key for IP context. |
| `SHODAN_API_KEY` | (empty) | Optional: Shodan key for host context. |

#### ueba

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8004` | Port the UEBA service listens on (fixed in the image's command). |
| `ENVIRONMENT` | `production` | Production posture: the development auth bypass is unreachable and insecure defaults refuse to boot. Do not change. |
| `AISOC_DEV_MODE` | `0` | Development mode off: routes never fall back to an anonymous or demo principal. Do not change. |
| `AISOC_PUBLISHED_BIND_ADDRS` | `0.0.0.0` | Tells the service it is reachable from other hosts, so the developer auth shim stays refused even if dev mode were switched on. |
| `AISOC_ALLOW_CLEARTEXT_KAFKA` | `1` | Allow PLAINTEXT Kafka in production: the broker is reachable only over Railway's private network, which Railway encrypts. Set KAFKA_SECURITY_PROTOCOL instead if you bring a TLS broker. |
| `AISOC_SERVICE_TOKEN` | `${{api.AISOC_SERVICE_TOKEN}}` | Shared service token. |
| `DATABASE_URL` | `postgresql+asyncpg://aisoc_app:${{api.AISOC_APP_DB_PASSWORD}}@${{Postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/${{Postgres.POSTGRES_DB}}` | Postgres as aisoc_app (runtime). |
| `DATABASE_MIGRATION_URL` | `postgresql+asyncpg://${{Postgres.POSTGRES_USER}}:${{Postgres.POSTGRES_PASSWORD}}@${{Postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/${{Postgres.POSTGRES_DB}}` | Owner connection for this service's own Alembic chain, applied at start. |
| `AISOC_APP_DB_PASSWORD` | `${{api.AISOC_APP_DB_PASSWORD}}` | Runtime role password (as upstream passes it). |
| `REDIS_URL` | `redis://default:${{Redis.REDIS_PASSWORD}}@${{Redis.RAILWAY_PRIVATE_DOMAIN}}:6379/8` | Redis (database 8). |
| `KAFKA_BOOTSTRAP_SERVERS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka-API broker (consumes aisoc.raw_events, publishes ueba.anomalies). |
| `CLICKHOUSE_URL` | `http://${{clickhouse.CLICKHOUSE_USER}}:${{clickhouse.CLICKHOUSE_PASSWORD}}@${{clickhouse.RAILWAY_PRIVATE_DOMAIN}}:8123/aisoc` | ClickHouse HTTP URL for baselines. |
| `CORE_API_URL` | `http://${{api.RAILWAY_PRIVATE_DOMAIN}}:8000` | Core API. |
| `OTEL_SDK_DISABLED` | `true` | Tracing off (no OpenTelemetry collector in this template). |

#### litellm

| Variable | Value | Description |
|---|---|---|
| `PORT` | `4000` | Port the gateway listens on; Railway's healthcheck probes it. |
| `LITELLM_MASTER_KEY` | `sk-${{secret(40, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Bearer every AiSOC service presents to the gateway (generated; upstream's compose default is a published literal). |
| `AISOC_LLM_MODEL_FAST` | `ollama_chat/${{ollama.OLLAMA_DEFAULT_MODEL}}` | Model behind the high-volume aliases (triage, summary, copilot, NL, hunt, detection). Any LiteLLM model string, e.g. openai/<model> with OPENAI_API_KEY set and AISOC_LLM_API_BASE emptied. |
| `AISOC_LLM_MODEL_DEEP` | `ollama_chat/${{ollama.OLLAMA_DEFAULT_MODEL}}` | Model behind the investigation and report aliases. |
| `AISOC_LLM_API_BASE` | `http://${{ollama.RAILWAY_PRIVATE_DOMAIN}}:11434` | API base for both models (the bundled Ollama). Set it to an empty value when you switch to a hosted provider. |
| `OPENAI_API_KEY` | (empty) | Optional: hosted-provider key (OpenAI or any OpenAI-compatible provider). Empty = the bundled local model answers. |
| `ANTHROPIC_API_KEY` | (empty) | Optional: Anthropic key, for anthropic/<model> strings. |
| `AISOC_LITELLM_REQUEST_TIMEOUT` | `300` | Seconds the gateway waits for one generation. 300 suits CPU-only inference (upstream default 60, raised per upstream issue #1241 guidance). |

#### ollama

| Variable | Value | Description |
|---|---|---|
| `PORT` | `11434` | Port Ollama listens on; Railway's healthcheck probes it. |
| `OLLAMA_HOST` | `[::]:11434` | Listen on IPv4 and IPv6. |
| `OLLAMA_PULL_MODELS` | `llama3.2:3b-instruct-q4_K_M` | Models pulled on first boot (comma-separated). Upstream's pinned CPU model, about 2 GB. |
| `OLLAMA_BASE_MODEL` | `llama3.2:3b-instruct-q4_K_M` | Model the CPU-tuned copy is created from. |
| `OLLAMA_DEFAULT_MODEL` | `aisoc-llama3.2:3b` | CPU-tuned copy (explicit thread count and context) that the LiteLLM aliases use. Recreated on every start. |
| `OLLAMA_NUM_THREAD` | (empty) | Optional override for the inference thread count. Empty = the service's CPU quota, capped at 8. |
| `OLLAMA_CONTEXT_LENGTH` | `8192` | Context window of the tuned model (tokens). |
| `OLLAMA_FLASH_ATTENTION` | `1` | Flash attention on (smaller KV cache). |
| `OLLAMA_KV_CACHE_TYPE` | `q8_0` | 8-bit KV cache (about half the memory of f16). |
| `OLLAMA_NUM_PARALLEL` | `1` | One generation at a time (CPU); other requests queue. |
| `OLLAMA_MAX_LOADED_MODELS` | `1` | Keep at most one model in memory. |
| `OLLAMA_KEEP_ALIVE` | `30m` | Unload the model after 30 idle minutes (frees about 2.5 GB). |

#### kafka

| Variable | Value | Description |
|---|---|---|
| `PORT` | `9644` | Redpanda admin API port; Railway's healthcheck probes /v1/status/ready here. |
| `REDPANDA_MEMORY` | `1G` | Memory Redpanda may use (Seastar would otherwise size itself to the host). Raise with the service's RAM. |
| `RAILWAY_RUN_UID` | `0` | Run as root so Redpanda can write the root-owned Railway volume. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `30` | Allow a clean shutdown on redeploy. |

#### qdrant

| Variable | Value | Description |
|---|---|---|
| `PORT` | `6333` | Qdrant HTTP port; Railway's healthcheck probes /readyz here. |
| `QDRANT__SERVICE__HOST` | `::` | Listen on IPv4 and IPv6. |
| `QDRANT__TELEMETRY_DISABLED` | `true` | No usage telemetry. |

#### clickhouse

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8123` | ClickHouse HTTP port; Railway's healthcheck probes /ping here. |
| `CLICKHOUSE_DB` | `aisoc` | Database created on first boot. |
| `CLICKHOUSE_USER` | `aisoc` | User created on first boot; replaces the passwordless default user. |
| `CLICKHOUSE_PASSWORD` | `${{secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Password of the ClickHouse user (generated). |
| `CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT` | `1` | Allow the user to manage access (as upstream). |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `30` | Allow a clean shutdown on redeploy. |

#### opensearch

| Variable | Value | Description |
|---|---|---|
| `PORT` | `9200` | OpenSearch HTTP port; Railway's healthcheck probes it. |
| `discovery.type` | `single-node` | Single-node cluster (also skips the production bootstrap checks). |
| `cluster.name` | `aisoc-cluster` | Cluster name (as upstream). |
| `node.name` | `aisoc-node-1` | Node name (as upstream). |
| `network.host` | `0.0.0.0` | Bind address (Java listens dual-stack). 0.0.0.0, not '::' (Rule: settings are passed through unquoted). |
| `bootstrap.memory_lock` | `false` | memlock ulimits cannot be raised on Railway (upstream sets true with an unlimited memlock). |
| `node.store.allow_mmap` | `false` | Do not depend on the host's vm.max_map_count. |
| `OPENSEARCH_JAVA_OPTS` | `-Xms512m -Xmx512m` | JVM heap (as upstream). The process settles near 1 GB RSS with this heap. |
| `DISABLE_INSTALL_DEMO_CONFIG` | `true` | No demo certificates or users (as upstream). |
| `DISABLE_SECURITY_PLUGIN` | `true` | Security plugin off as upstream: reachable only on the private network, and the threatintel client connects without credentials. |
| `DISABLE_PERFORMANCE_ANALYZER_AGENT_CLI` | `true` | Skip the performance-analyzer side process (saves memory; AiSOC does not use it). |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `30` | Allow a clean shutdown on redeploy. |

#### neo4j

| Variable | Value | Description |
|---|---|---|
| `PORT` | `7474` | Neo4j HTTP port; Railway's healthcheck probes it. |
| `AISOC_NEO4J_PASSWORD` | `${{secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Password of the neo4j user (generated). Not prefixed `NEO4J_`, because the Neo4j image turns every `NEO4J_*` variable into a config setting and refuses unknown ones. |
| `NEO4J_AUTH` | `neo4j/${{AISOC_NEO4J_PASSWORD}}` | Initial credentials, applied on first boot. |
| `NEO4J_PLUGINS` | `["apoc"]` | APOC core (bundled in the image, as upstream). |
| `NEO4J_dbms_security_procedures_unrestricted` | `apoc.*` | Allow APOC procedures (as upstream). |
| `NEO4J_server_memory_heap_initial__size` | `256m` | JVM heap start (upstream values, Neo4j 5 setting names). |
| `NEO4J_server_memory_heap_max__size` | `512m` | JVM heap limit. |
| `NEO4J_server_memory_pagecache_size` | `256m` | Page cache (Neo4j would otherwise size it from host memory). |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `30` | Allow a clean shutdown on redeploy. |

#### Postgres

| Variable | Value | Description |
|---|---|---|
| `PGDATA` | `/var/lib/postgresql/data/pgdata` | Location where the database will be initialized. |
| `PGHOST` | `${{RAILWAY_PRIVATE_DOMAIN}}` | Railway private domain name. |
| `PGPORT` | `5432` | Port to connect to Postgres. |
| `PGUSER` | `${{ POSTGRES_USER }}` | Required variable for the Data panel. |
| `PGDATABASE` | `${{POSTGRES_DB}}` | Required variable for the Data panel. |
| `PGPASSWORD` | `${{POSTGRES_PASSWORD}}` | Required variable for the Data panel. |
| `POSTGRES_DB` | `aisoc` | Database created on first boot (AiSOC's name for it). |
| `POSTGRES_USER` | `aisoc` | Owner/superuser role. Only the API's migration step and UEBA's migrations connect as it; every service runs as aisoc_app. |
| `POSTGRES_PASSWORD` | `${{ secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") }}` | Password of the owner role (generated). |
| `DATABASE_URL` | `postgresql://${{PGUSER}}:${{POSTGRES_PASSWORD}}@${{RAILWAY_PRIVATE_DOMAIN}}:5432/${{PGDATABASE}}` | Owner connection URL (for the Data panel and admin work). |
| `SSL_CERT_DAYS` | `820` | SSL certificate expiry in days. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Allow Postgres to cleanly shut down. |

#### Redis

| Variable | Value | Description |
|---|---|---|
| `REDISHOST` | `${{RAILWAY_PRIVATE_DOMAIN}}` | Private network hostname of the Redis service. |
| `REDISPORT` | `6379` | Port that Redis listens on. |
| `REDISUSER` | `default` | Username for authenticating with Redis. |
| `REDIS_PASSWORD` | `${{ secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") }}` | Randomly generated password for authenticating with Redis. |
| `REDISPASSWORD` | `${{REDIS_PASSWORD}}` | Alias of REDIS_PASSWORD for clients that expect the unseparated name. |
| `REDIS_URL` | `redis://${{ REDISUSER }}:${{ REDIS_PASSWORD }}@${{ REDISHOST }}:${{ REDISPORT }}` | Connection string on the private network. |

## Verification checklist

- [ ] The four repo builds succeed (clickhouse, opensearch, litellm, ollama).
- [ ] Postgres up; **api pre-deploy** log: `Found 138 migration files; connecting as 'aisoc'`, `✓ applied …` lines, `runtime role aisoc_app: login credential applied`, then `Administrator created. Sign in at https://{web-domain}` (password not echoed), then no `not reachable` lines (or only for services still starting).
- [ ] api healthy on `/readyz`; its log shows no `InsecureProductionDefaultsError` and no `Neo4j unavailable at startup`.
- [ ] kafka healthy; `rpk cluster info` (kafka shell) lists the broker at `kafka.railway.internal:9092`.
- [ ] fusion, agents, actions, connectors, threatintel, ueba healthy on `/readyz`; realtime on `/healthz`; enrichment on `/health`; ingest on `/readyz`; log of ingest shows `graph: ingest-side writer enabled`.
- [ ] clickhouse log: `/entrypoint.sh: running /docker-entrypoint-initdb.d/001_init.sql` on the first boot only.
- [ ] opensearch healthy (`/_cluster/health` green or yellow); log shows the node started as a non-root user.
- [ ] ollama log: `inference threads: N (source: cgroup-cpu-quota=Q…)` (record Q), `model llama3.2:3b-instruct-q4_K_M ready`, `model aisoc-llama3.2:3b ready`.
- [ ] `curl https://{web-domain}/api/v1/cases` and `curl -X POST https://{web-domain}/api/v1/cases -d '{}'` without credentials → 401/403.
- [ ] `curl -X POST https://{ingest-domain}/v1/ingest -d '{}'` without a token → 401; with `Authorization: Bearer {AISOC_SERVICE_TOKEN}` but no `X-Tenant-ID` → 403.
- [ ] `curl https://{web-domain}/api/v1/enrichment/lookup -X POST` → 5xx (proxy closed), never an enrichment result.
- [ ] Sign in; wizard → **Load sample data** → five alerts appear; at least one shows an AI triage verdict from `aisoc-llama3.2:3b` (cost dashboard shows tokens).
- [ ] Threat Intelligence lists CISA KEV entries.
- [ ] A proposed response (e.g. isolate host) shows as awaiting approval, not executed.
- [ ] agents log: `ATT&CK bundle cached locally` on the first start, `Loading MITRE ATT&CK from local file` after a redeploy.
- [ ] Create a playbook in the console; redeploy agents; it is still there.
- [ ] Redeploy all services: sign-in, alerts, threat intel and the pulled model persist; the pre-deploy reports `An administrator already exists`.

## Open questions

- Nothing was built or run (no Docker in this round): the four Dockerfiles, both start-command wrappers and the pre-deploy were checked with `bash -n`/`sh -n` and stub runs only.
- **Redpanda vs cp-kafka:** AiSOC is tested upstream against Confluent Kafka 7.5. aiokafka, kafka-go and kafkajs all support Redpanda, and upstream's threatintel defaults to `redpanda:9092`, but the full pipeline has not run on Redpanda here.
- **PostgreSQL 18** with the 138-file migration chain (upstream tests 16). Strict mode makes any failure visible in the pre-deploy log.
- **OpenSearch privilege drop** via `chroot --userspec` on Amazon Linux 2 coreutils (checked: the base layer ships `/usr/sbin/chroot` and no `setpriv`/`runuser`).
- **Ollama 0.40.3** with upstream's model through LiteLLM `ollama_chat/`, and CPU triage latency on Railway; if triage times out, lower `OLLAMA_CONTEXT_LENGTH`, try `OLLAMA_NUM_THREAD` one below the vCPU limit, or use a hosted model.
- WebSocket/SSE through the console's Next.js rewrites on Railway (upstream's design).
- First-deploy timing of `/readyz` for the workers (900 s window) while Kafka and the stores start in parallel.
- `PASSKEY_RP_ORIGINS` is a JSON list for pydantic-settings; passkeys on the `*.up.railway.app` domain were not tried.
- The sample-data button posts to `INGEST_PUBLIC_URL` (the public ingest domain) with the shared service token over HTTPS; upstream prefers that variable over the private URL.
