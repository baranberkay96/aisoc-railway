# LiteLLM gateway for AiSOC on Railway.
#
# Same image and version AiSOC v20.3.0 pins in docker-compose.yml
# (ghcr.io/berriai/litellm:v1.102.1, here also pinned by digest). Upstream
# bind-mounts infra/litellm/config.yaml; Railway cannot bind-mount, so the file
# (MIT, copied unchanged from AiSOC v20.3.0) is baked in. Every alias in it reads
# its model, API base and keys from the environment (os.environ/...), so
# switching from the bundled Ollama model to a hosted provider is a variable
# change, not a rebuild.
FROM ghcr.io/berriai/litellm:v1.102.1@sha256:87f34979b9f8cb274fac90ca8a4fdda07d8480de22755562a26adeb95ce20d02

COPY config.yaml /etc/litellm/config.yaml
RUN chmod 0644 /etc/litellm/config.yaml

EXPOSE 4000

# The image's ENTRYPOINT (docker/prod_entrypoint.sh) runs `litellm "$@"`.
CMD ["--config", "/etc/litellm/config.yaml", "--port", "4000"]
