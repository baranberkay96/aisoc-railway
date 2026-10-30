#!/bin/bash
# Thin wrapper around the official ClickHouse entrypoint for AiSOC on Railway.
#
# - Refuses to start without a password: the official entrypoint would otherwise
#   keep the passwordless "default" user.
# - Removes lost+found from a fresh Railway volume, so the data directory is
#   empty on first boot and the init script (001_init.sql) runs exactly once.
set -euo pipefail

fail() { echo "railway: FATAL: $*" >&2; exit 1; }

[ -n "${CLICKHOUSE_USER:-}" ] || fail "CLICKHOUSE_USER must be set (see the template variables)."
[ "${CLICKHOUSE_USER}" != "default" ] || fail "CLICKHOUSE_USER must not be 'default'."
[ -n "${CLICKHOUSE_PASSWORD:-}" ] || fail "CLICKHOUSE_PASSWORD must be set (see the template variables)."

rm -rf /var/lib/clickhouse/lost+found 2>/dev/null || true

echo "railway: starting ClickHouse (user=${CLICKHOUSE_USER}, database=${CLICKHOUSE_DB:-default})"
exec /entrypoint.sh "$@"
