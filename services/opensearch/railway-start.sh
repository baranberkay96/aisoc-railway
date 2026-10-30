#!/bin/bash
# Railway volumes are mounted root-owned and OpenSearch refuses to run as root.
# Fix the data directory's ownership, then run the image's own entrypoint as
# uid/gid 1000 (the image's "opensearch" user).
#
# The base image (Amazon Linux 2) has coreutils chroot but no setpriv/runuser,
# and its chroot is too old for --skip-chdir. chroot --userspec therefore drops
# privileges and resets the working directory to /, so the command below cds
# back to OPENSEARCH_HOME before it runs ./opensearch-docker-entrypoint.sh,
# which the image expects to start from there. The environment (including the
# dotted OpenSearch settings such as discovery.type) passes through unchanged.
set -euo pipefail

OPENSEARCH_HOME=/usr/share/opensearch
DATA_DIR="${OPENSEARCH_HOME}/data"
OS_UID=1000
OS_GID=1000

if [ "$(id -u)" != "0" ]; then
    cd "$OPENSEARCH_HOME"
    exec ./opensearch-docker-entrypoint.sh "$@"
fi

mkdir -p "$DATA_DIR"
rm -rf "${DATA_DIR}/lost+found"
chown -R "${OS_UID}:${OS_GID}" "$DATA_DIR"
chmod 1777 /tmp

export HOME="$OPENSEARCH_HOME"
exec chroot --userspec="${OS_UID}:${OS_GID}" / /bin/bash -c \
    'cd /usr/share/opensearch && exec ./opensearch-docker-entrypoint.sh "$@"' railway-opensearch "$@"
