# Deploy and Host AiSOC with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/aisoc-v20-ai-security-operations-center?referralCode=20H68q)

AiSOC is an open-source, self-hostable AI Security Operations Center. This template deploys its full v20.3.0 production stack on Railway in one step. It covers telemetry ingest, detection, correlation, an event lake, an entity graph and threat intel. AI triage runs on a bundled local model, and actions that change vendor systems wait for human approval. No API key is required.

## About Hosting AiSOC

AiSOC takes security telemetry from your tools through an authenticated ingest API or 80+ connectors and normalizes it. Fusion matches it against a large detection library and groups what fires into incidents. AI agents then triage those incidents and record every prompt and tool call. Proposed responses go to an approval queue.

Hosting it means running about twenty cooperating services: the console, API and workers, a Kafka-API broker, Postgres, Redis, ClickHouse, OpenSearch, Neo4j, Qdrant, and an LLM gateway with a local model. This template wires them on Railway's private network. It generates every secret and creates the first administrator. Only the console and the ingest endpoint are public. This is a community template and is not affiliated with or endorsed by the AiSOC project.

## Common Use Cases

- Run a self-hosted SOC console that ingests alerts from EDR, SIEM, identity and cloud tools, then deduplicates and correlates them into incidents.
- Triage alert queues with AI agents whose reasoning is recorded and auditable, using a local model or your own LLM provider.
- Hunt over an event lake (ClickHouse) and an entity graph (Neo4j), enriched with public threat intelligence such as the CISA KEV catalogue.
- Keep response actions such as host isolation and account disablement behind an explicit human approval step.
- Evaluate AiSOC end to end with the built-in sample data before you connect production sources.

## Dependencies for AiSOC Hosting

- AiSOC v20.3.0 images (web, api, ingest, fusion, agents, actions, connectors, threatintel, realtime, enrichment, ueba)
- PostgreSQL 18 (Railway), Redis 8.2
- Redpanda (Kafka API) as the event spine
- ClickHouse 23.8 (event lake), OpenSearch 2.11 (IOC index), Neo4j 5.15 (entity graph), Qdrant 1.19 (vectors)
- LiteLLM gateway and Ollama with `llama3.2:3b-instruct-q4_K_M` (local CPU model, about 2 GB)

### Deployment Dependencies

- AiSOC source and releases: https://github.com/beenuar/AiSOC
- AiSOC documentation: https://beenuar.github.io/AiSOC/
- Console getting started: https://beenuar.github.io/AiSOC/docs/console/getting-started
- LiteLLM: https://docs.litellm.ai/
- Ollama model: https://ollama.com/library/llama3.2 (Llama 3.2 Community License: https://www.llama.com/llama3_2/license/)
- Redpanda: https://docs.redpanda.com/
- ClickHouse: https://clickhouse.com/docs
- OpenSearch: https://opensearch.org/docs/latest/
- Neo4j: https://neo4j.com/docs/
- Qdrant: https://qdrant.tech/documentation/
- Railway private networking: https://docs.railway.com/reference/private-networking

### Implementation Details

| Service | Role | Public |
|---|---|---|
| web | Next.js console; proxies the API, agents and realtime on the private network | yes |
| ingest | Telemetry endpoint (`/v1/ingest`, `/v1/inbox/*`), token required | yes |
| api | Core API; pre-deploy runs the SQL migrations and creates the administrator | no |
| fusion | Detection engine, correlation, alerts, ClickHouse lake writer (volume for its spool) | no |
| agents | AI triage, investigations, copilot, hunts, playbooks (volume for playbooks) | no |
| actions | Governed response actions with human approval | no |
| connectors | Vendor pollers and federated search; credentials encrypted at rest | no |
| threatintel | CISA KEV, OTX and MISP feeds into Qdrant and OpenSearch | no |
| realtime | Live updates over WebSocket/SSE | no |
| enrichment, ueba | IOC enrichment; behavioural baselines | no |
| litellm, ollama | LLM gateway and local CPU model | no |
| kafka, Postgres, Redis, clickhouse, opensearch, neo4j, qdrant | Data plane, each with its own volume | no |

**First login**

1. Wait until `api` and `web` are healthy. The first deploy pulls about 8 GB of images and builds four small wrapper images. The local model downloads in the background.
2. Open the `web` URL and sign in with `AISOC_ADMIN_EMAIL` (default `admin@aisoc.internal`) and `AISOC_ADMIN_PASSWORD`, found under the `api` service's Variables.
3. In the setup wizard, press **Load sample data**. Five labelled events go through the real pipeline and become alerts with AI triage.
4. Mint a push token in the wizard and send telemetry to `https://{ingest-domain}/v1/ingest` with `Authorization: Bearer {token}`, or add connectors in the console.

**Using your own LLM:** set it per tenant in the console (Settings → Deployment & AI). For the whole deployment, set `OPENAI_API_KEY` (or `ANTHROPIC_API_KEY`) and the two `AISOC_LLM_MODEL_*` variables on `litellm`, then clear `AISOC_LLM_API_BASE`.

**Scaling:** `web`, `api`, `ingest`, `actions` and `enrichment` can take more replicas. `fusion` and `agents` keep one replica because they use volumes, so give them more memory instead. Kafka topics are created with one partition; add partitions before you scale consumers.

**Versions and upgrades:** all AiSOC images are pinned to `v20.3.0`. To upgrade, change the tag on all eleven `ghcr.io/beenuar/aisoc-*` images together and redeploy. The pre-deploy step applies new migrations and fails the deploy if one fails. Third-party images are pinned by tag or digest.

**Cost:** about $57/month idle and about $150/month with typical use (estimates). Hobby is the minimum plan. Pro is recommended for real telemetry volumes.

### Why Deploy AiSOC on Railway?

Railway runs the full multi-service AiSOC stack without you having to manage servers or Docker hosts. The data stores sit on an encrypted private network, each with a persistent volume, and only the console and ingest endpoint are exposed over HTTPS. Secrets are generated at deploy time. You can scale web and API replicas, add memory to workers, or switch to a hosted LLM by changing variables.
