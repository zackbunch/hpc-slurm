#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

"${SCRIPT_DIR}/setup_ssh.sh"
load_ssh_options
load_remote_env "${JOB_ENV_FILE:-job.env}"
require_var HPC_JOB_ID
[[ "$HPC_JOB_ID" =~ ^[0-9]+$ ]] || die "HPC_JOB_ID must be numeric"
slurm_cluster_args

poll_seconds="${SLURM_POLL_SECONDS:-15}"
timeout_seconds="${SLURM_WAIT_TIMEOUT_SECONDS:-3600}"
[[ "$poll_seconds" =~ ^[1-9][0-9]*$ ]] || die "SLURM_POLL_SECONDS must be a positive integer"
[[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || die "SLURM_WAIT_TIMEOUT_SECONDS must be a positive integer"
deadline=$((SECONDS + timeout_seconds))
last_state=''

while (( SECONDS < deadline )); do
  queue_state="$(ssh_exec squeue "${SLURM_CLUSTER_ARGS[@]}" --noheader --jobs "$HPC_JOB_ID" --format %T | head -n1 | tr -d '[:space:]')"
  if [[ -n "$queue_state" ]]; then
    if [[ "$queue_state" != "$last_state" ]]; then
      log "job ${HPC_JOB_ID} state: ${queue_state}"
      last_state="$queue_state"
    fi
    sleep "$poll_seconds"
    continue
  fi

  accounting="$(ssh_exec sacct "${SLURM_CLUSTER_ARGS[@]}" -X --jobs "$HPC_JOB_ID" --noheader --parsable2 --format State,ExitCode | sed '/^[[:space:]]*$/d' | head -n1)"
  if [[ -z "$accounting" ]]; then
    log "job left squeue; waiting for accounting record"
    sleep "$poll_seconds"
    continue
  fi

  IFS='|' read -r state exit_code <<<"$accounting"
  state="${state%%+*}"
  state="${state//[[:space:]]/}"
  exit_code="${exit_code//[[:space:]]/}"
  primary_exit="${exit_code%%:*}"
  printf 'SLURM_FINAL_STATE=%s\nSLURM_EXIT_CODE=%s\n' "$state" "$exit_code" >slurm-status.env
  log "job ${HPC_JOB_ID} terminal state=${state} exit_code=${exit_code}"

  if [[ "$state" == "COMPLETED" && "$primary_exit" == "0" ]]; then
    exit 0
  fi
  die "Slurm job did not complete successfully"
done

log "CI wait timeout reached; requesting cancellation of job ${HPC_JOB_ID}"
ssh_exec scancel "${SLURM_CLUSTER_ARGS[@]}" "$HPC_JOB_ID" || true
printf 'SLURM_FINAL_STATE=CI_WAIT_TIMEOUT\nSLURM_EXIT_CODE=124:0\n' >slurm-status.env
exit 124

