#!/usr/bin/env bash

# Resource settings are supplied by scripts/submit_slurm.sh so they remain configurable.
set -Eeuo pipefail
umask 077

JOB_WORK_DIR="${SLURM_SUBMIT_DIR:?SLURM_SUBMIT_DIR is not set}"
cd "$JOB_WORK_DIR"

# shellcheck disable=SC1091
source "${JOB_WORK_DIR}/job.env"
: "${HPC_CONTAINER:?HPC_CONTAINER is not configured}"

mkdir -p "${JOB_WORK_DIR}/results"
SIM_ARGV=()
while IFS= read -r encoded_arg; do
  [[ -n "$encoded_arg" ]] || continue
  SIM_ARGV+=("$(printf '%s' "$encoded_arg" | base64 --decode)")
done <"${JOB_WORK_DIR}/sim.args.b64"

APPTAINER_ARGS=(
  exec
  --cleanenv
  --bind "${JOB_WORK_DIR}:${JOB_WORK_DIR}"
  --cwd "$JOB_WORK_DIR"
)
if [[ -n "${APPTAINER_EXTRA_BINDS:-}" ]]; then
  APPTAINER_ARGS+=(--bind "$APPTAINER_EXTRA_BINDS")
fi

start_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
set +e
apptainer "${APPTAINER_ARGS[@]}" "$HPC_CONTAINER" ./sim "${SIM_ARGV[@]}"
simulation_rc=$?
set -e
end_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
  printf 'job_id=%s\n' "${SLURM_JOB_ID:-unknown}"
  printf 'node_list=%s\n' "${SLURM_JOB_NODELIST:-unknown}"
  printf 'container=%s\n' "$HPC_CONTAINER"
  printf 'started_utc=%s\n' "$start_utc"
  printf 'finished_utc=%s\n' "$end_utc"
  printf 'simulation_exit_code=%s\n' "$simulation_rc"
} >"${JOB_WORK_DIR}/job-summary.txt"

exit "$simulation_rc"

