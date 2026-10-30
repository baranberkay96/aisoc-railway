# Notices

This is a community Railway template for AiSOC. It is not affiliated with or endorsed by the AiSOC project or its sponsors.

## Upstream checked

- Repository: https://github.com/beenuar/AiSOC, release **v20.3.0** (tag commit `e3edeb857ddd1a4a5f939d06d67080f204be88a8`, published 2026-10-30).
- Files the template follows: `docker-compose.yml` and `docker-compose.prod.yml` (production overlay), plus `infra/litellm/config.yaml`, `infra/postgres/initdb/*`, `services/api/clickhouse/001_init.sql`, `apps/web/next.config.js`, `apps/web/docker-entrypoint.sh`, `.env.example`, `scripts/ensure_env.py` and the services' settings modules at that tag.
- Images: `ghcr.io/beenuar/aisoc-*:v20.3.0`; their `org.opencontainers.image.revision` label is the tag commit above.

## Reused from AiSOC (MIT)

Two files are copied unchanged from AiSOC v20.3.0 and baked into images, because Railway cannot bind-mount them:

| File in this package | Upstream path |
|---|---|
| `services/litellm/config.yaml` | `infra/litellm/config.yaml` |
| `services/clickhouse/001_init.sql` | `services/api/clickhouse/001_init.sql` |

AiSOC's license:

```
MIT License

Copyright (c) 2024-present AiSOC contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

**Name and logo.** AiSOC's `TRADEMARK.md` keeps the name and logo outside the MIT grant. This template uses the name only to describe the software it deploys (the unmodified upstream images). It does not use the AiSOC logo: the listing icon is Lucide's `shield-check`.

## Written for this template

`template.json`, `TEMPLATE.md`, `README.md`, this file, and the Dockerfiles and scripts under `services/` (except the two files above) were written for this package. The Ollama entrypoint is adapted from this repository's own Odysseus template. The Redpanda start command and the Railway Postgres/Redis definitions come from this repository's other templates and Railway's base templates.

## Third-party software deployed (unmodified images, pulled at deploy time)

| Component | License |
|---|---|
| PostgreSQL (`ghcr.io/railwayapp-templates/postgres-ssl:18`) | PostgreSQL License |
| Redis 8.2 | RSALv2 / SSPLv1 / AGPLv3 (tri-license) |
| Redpanda Community Edition v24.3 | Business Source License 1.1 (free for self-hosted use; not for offering Redpanda itself as a managed streaming service) |
| ClickHouse 23.8 | Apache-2.0 |
| OpenSearch 2.11 | Apache-2.0 |
| Neo4j 5.15 Community Edition (with bundled APOC core) | GPLv3 (APOC: Apache-2.0) |
| Qdrant 1.19 | Apache-2.0 |
| LiteLLM v1.102.1 | MIT (the `enterprise/` directory is under a separate license and is not used) |
| Ollama 0.40.3 | MIT |
| Llama 3.2 3B Instruct weights (pulled by your deployment from the Ollama library) | Llama 3.2 Community License and Acceptable Use Policy |
| Lucide icons (listing and service icons) | ISC |
| Service icons from homarr-labs/dashboard-icons (Ollama, Kafka, Qdrant, ClickHouse, OpenSearch, Neo4j) | Apache-2.0 collection; the logos are their owners' marks |
