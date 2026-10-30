# ClickHouse event lake for AiSOC on Railway.
#
# Same server line as AiSOC v20.3.0's docker-compose.yml (clickhouse-server 23.8,
# here the last 23.8 LTS patch, pinned by digest). Upstream bind-mounts
# services/api/clickhouse into /docker-entrypoint-initdb.d; Railway cannot
# bind-mount, so 001_init.sql (MIT, copied unchanged from AiSOC v20.3.0) is baked
# in. The image entrypoint runs it once, on an empty data volume. Later lake
# migrations are applied by the AiSOC API at startup (app/db/lake_migrations.py).
FROM clickhouse/clickhouse-server:23.8.16.16@sha256:1bf47c6885ba436d7d162a739482126a073a3c5b6080df379d732f14c1d9f662

COPY 001_init.sql /docker-entrypoint-initdb.d/001_init.sql
COPY config.d/railway.xml /etc/clickhouse-server/config.d/railway.xml
COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod 0644 /docker-entrypoint-initdb.d/001_init.sql /etc/clickhouse-server/config.d/railway.xml \
 && chmod 0755 /usr/local/bin/railway-entrypoint.sh

EXPOSE 8123 9000

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
