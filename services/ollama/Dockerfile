# Local CPU model server for AiSOC on Railway (the backend of the LiteLLM
# gateway's aisoc-* aliases, so AI triage works without an API key).
#
# AiSOC v20.3.0 pins ollama/ollama:0.6.7 plus a one-shot "ollama-pull" container.
# This uses 0.40.3 (pinned by digest) because its llama.cpp runner honours
# LLAMA_ARG_THREADS, and the entrypoint below sizes the thread pool from the
# service's CPU quota: on Railway's many-core hosts Ollama otherwise starts one
# thread per visible core and CPU inference stalls. The entrypoint also pulls
# the model on first boot (replacing the one-shot pull container) and creates a
# CPU-tuned copy with an explicit thread count and context size.
# Private network only.
FROM ollama/ollama:0.40.3@sha256:adca95a12c2b386a8f9a995e7fa0600e187e3323b5e5522f5a6c3b1ec73eff99

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod 0755 /usr/local/bin/railway-entrypoint.sh

ENV OLLAMA_HOST=[::]:11434
EXPOSE 11434
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
