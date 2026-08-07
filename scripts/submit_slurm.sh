#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

"${SCRIPT_DIR}/setup_ssh.sh"
load_ssh_options
load_remote_env "${REMOTE_ENV_FILE:-remote.env}"
slurm_cluster_args

SLURM_TIME="${SLURM_TIME:-00:30:00}"
SLURM_NODES="${SLURM_NODES:-1}"
SLURM_TASKS="${SLURM_TASKS:-1}"
SLURM_CPUS="${SLURM_CPUS:-1}"
SLURM_MEMORY="${SLURM_MEMORY:-1G}"
[[ "$SLURM_TIME" =~ ^[0-9]+-[0-9]{2}:[0-9]{2}:[0-9]{2}$|^[0-9]{1,2}:[0-9]{2}:[0-9]{2}$ ]] || die "invalid SLURM_TIME"
[[ "$SLURM_NODES" =~ ^[1-9][0-9]*$ ]] || die "invalid SLURM_NODES"
[[ "$SLURM_TASKS" =~ ^[1-9][0-9]*$ ]] || die "invalid SLURM_TASKS"
[[ "$SLURM_CPUS" =~ ^[1-9][0-9]*$ ]] || die "invalid SLURM_CPUS"
[[ "$SLURM_MEMORY" =~ ^[1-9][0-9]*[KMGT]?$ ]] || die "invalid SLURM_MEMORY"

SBATCH_ARGS=(
  sbatch
  --parsable
  "${SLURM_CLUSTER_ARGS[@]}"
  --job-name "gl-${CI_PIPELINE_ID:-manual}"
  --chdir "$HPC_REMOTE_DIR"
  --output "${HPC_REMOTE_DIR}/slurm-%j.out"
  --error "${HPC_REMOTE_DIR}/slurm-%j.err"
  --time "$SLURM_TIME"
  --nodes "$SLURM_NODES"
  --ntasks "$SLURM_TASKS"
  --cpus-per-task "$SLURM_CPUS"
  --mem "$SLURM_MEMORY"
)

for pair in "SLURM_ACCOUNT:--account" "SLURM_PARTITION:--partition" "SLURM_QOS:--qos"; do
  var_name="${pair%%:*}"
  flag="${pair#*:}"
  if [[ -n "${!var_name:-}" ]]; then
    validate_simple_name "$var_name" "${!var_name}"
    SBATCH_ARGS+=("$flag" "${!var_name}")
  fi
done
SBATCH_ARGS+=("${HPC_REMOTE_DIR}/run_sim.slurm")

log "submitting Slurm job"
raw_job_id="$(ssh_exec "${SBATCH_ARGS[@]}")"
raw_job_id="${raw_job_id//$'\r'/}"
raw_job_id="${raw_job_id//$'\n'/}"
[[ "$raw_job_id" =~ ^[0-9]+(\;[A-Za-z0-9._-]+)?$ ]] || die "unexpected sbatch response: ${raw_job_id}"
HPC_JOB_ID="${raw_job_id%%;*}"

printf 'HPC_JOB_ID=%s\nHPC_REMOTE_DIR=%s\n' "$HPC_JOB_ID" "$HPC_REMOTE_DIR" >job.env
log "submitted Slurm job ${HPC_JOB_ID}"

