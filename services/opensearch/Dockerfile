# OpenSearch for AiSOC on Railway (threat-intel IOC/actor index used by the
# threatintel service). Same 2.11 line as AiSOC v20.3.0's docker-compose.yml
# (2.11.0 there; 2.11.1 is the last patch of that line), pinned by digest.
#
# Railway mounts volumes root-owned and OpenSearch refuses to run as root, so
# the container starts as root only to fix the data directory's ownership and
# then runs the image's own entrypoint as uid/gid 1000 (railway-start.sh).
FROM opensearchproject/opensearch:2.11.1@sha256:cbca8e35fb333af938289ac0f370abdcbde46dbe7629acc1af0cd4219da85b62

USER root
COPY railway-start.sh /usr/local/bin/railway-start.sh
RUN chmod 0755 /usr/local/bin/railway-start.sh

EXPOSE 9200

ENTRYPOINT ["/usr/local/bin/railway-start.sh"]
CMD ["opensearch"]
