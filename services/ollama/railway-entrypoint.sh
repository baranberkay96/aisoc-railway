#!/bin/bash
# Ollama on Railway CPU for AiSOC.
#
# 1. Sizes the inference thread pool: the service's CPU quota, at most 8
#    (OLLAMA_NUM_THREAD overrides). Ollama's llama.cpp runner otherwise starts
#    one thread per visible core (dozens on Railway hosts), far more than the
#    CPU time the service gets, and generation stalls. The count is exported as
#    LLAMA_ARG_THREADS, which every llama-server Ollama starts inherits.
# 2. Runs "ollama serve" and pulls OLLAMA_PULL_MODELS if they are missing
#    (first boot only; the weights live on the volume).
# 3. (Re)creates OLLAMA_DEFAULT_MODEL from OLLAMA_BASE_MODEL on every start with
#    num_thread and num_ctx set explicitly (manifest only, no new weights).
#    The LiteLLM gateway's aisoc-* aliases point at this model.
# The API keeps serving if a pull or create step fails; AiSOC then falls back to
# its deterministic triage path until the next start.
set -uo pipefail

CGROUP_ROOT=/sys/fs/cgroup
PROC_CGROUP=/proc/self/cgroup
# Upper bound for the automatic thread count. A 3B model gains little beyond 8
# threads, and spin-waiting llama.cpp threads degrade sharply when they
# outnumber the CPU time actually granted. OLLAMA_NUM_THREAD can set any value.
AUTO_THREAD_CAP=8

log() { echo "[railway] $*"; }

# floor(quota/period) of the tightest CPU quota visible to this container
# (cgroup v2 cpu.max of the own cgroup and its visible ancestors, then cgroup v1
# cfs quota). Prints nothing when every level is unlimited.
cgroup_cpu_limit() {
    local best="" quota period dir rel d

    consider() {
        [[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]] || return 0
        (( $2 > 0 )) || return 0
        local n=$(( $1 / $2 ))
        (( n < 1 )) && n=1
        if [[ -z "$best" ]] || (( n < best )); then best=$n; fi
    }

    if [[ -r "$CGROUP_ROOT/cgroup.controllers" ]]; then
        rel="$(awk -F: '$1 == "0" { print $3; exit }' "$PROC_CGROUP" 2>/dev/null)"
        dir="$CGROUP_ROOT${rel%/}"
        while [[ "$dir" == "$CGROUP_ROOT"* ]]; do
            if [[ -r "$dir/cpu.max" ]]; then
                read -r quota period < "$dir/cpu.max" && consider "$quota" "$period"
            fi
            [[ "$dir" == "$CGROUP_ROOT" ]] && break
            dir="$(dirname "$dir")"
        done
    fi
    for d in "$CGROUP_ROOT/cpu" "$CGROUP_ROOT/cpu,cpuacct" "$CGROUP_ROOT/cpuacct,cpu"; do
        if [[ -r "$d/cpu.cfs_quota_us" && -r "$d/cpu.cfs_period_us" ]]; then
            consider "$(cat "$d/cpu.cfs_quota_us")" "$(cat "$d/cpu.cfs_period_us")"
        fi
    done
    [[ -n "$best" ]] && echo "$best"
    return 0
}

# Prints "<threads> <source>".
resolve_threads() {
    local n source
    if [[ "${OLLAMA_NUM_THREAD:-}" =~ ^[1-9][0-9]*$ ]]; then
        echo "$OLLAMA_NUM_THREAD OLLAMA_NUM_THREAD"
        return
    fi
    n="$(cgroup_cpu_limit)"
    if [[ -n "$n" ]]; then
        source="cgroup-cpu-quota=$n"
    else
        n="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
        source="no-quota-visible,nproc=$n"
    fi
    if (( n > AUTO_THREAD_CAP )); then
        echo "$AUTO_THREAD_CAP $source,capped"
    else
        echo "$n $source"
    fi
}

read -r THREADS THREAD_SOURCE < <(resolve_threads)
export LLAMA_ARG_THREADS="$THREADS"
log "inference threads: $THREADS (source: $THREAD_SOURCE)"

/bin/ollama serve &
server_pid=$!
trap 'kill -TERM "$server_pid" 2>/dev/null; wait "$server_pid"; exit $?' TERM INT

client() { OLLAMA_HOST=127.0.0.1:11434 /bin/ollama "$@"; }

for _ in $(seq 1 120); do
    client list >/dev/null 2>&1 && break
    sleep 1
done

pull_models() {
    local model
    for model in ${OLLAMA_PULL_MODELS//,/ }; do
        if client show "$model" >/dev/null 2>&1; then
            log "model $model already present"
        else
            log "pulling $model (first boot only)"
            if client pull "$model" >/dev/null; then
                log "model $model ready"
            else
                log "WARNING: pull of $model failed; redeploy the ollama service to retry"
            fi
        fi
    done
}

create_default_model() {
    local base="${OLLAMA_BASE_MODEL:-}" name="${OLLAMA_DEFAULT_MODEL:-}"
    local ctx="${OLLAMA_CONTEXT_LENGTH:-8192}" dir
    if [[ -z "$base" || -z "$name" || "$name" == "$base" ]]; then
        return 0
    fi
    if [[ ! "$ctx" =~ ^[1-9][0-9]*$ ]]; then
        log "WARNING: OLLAMA_CONTEXT_LENGTH='$ctx' is not a number; using 8192"
        ctx=8192
    fi
    if ! client show "$base" >/dev/null 2>&1; then
        log "WARNING: base model $base is missing; $name not created"
        return 0
    fi
    dir="$(mktemp -d)"
    printf 'FROM %s\nPARAMETER num_thread %s\nPARAMETER num_ctx %s\n' "$base" "$THREADS" "$ctx" > "$dir/Modelfile"
    if client create "$name" -f "$dir/Modelfile" >/dev/null; then
        log "model $name ready ($base, $THREADS threads, ctx $ctx)"
    else
        log "WARNING: creating $name failed; AI triage falls back to AiSOC's deterministic path until the next start"
    fi
    rm -rf "$dir"
}

pull_models
create_default_model

wait "$server_pid"
