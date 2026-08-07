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

mkdir -p results
for remote_name in "slurm-${HPC_JOB_ID}.out" "slurm-${HPC_JOB_ID}.err" "job-summary.txt"; do
  scp "${SCP_OPTS[@]}" "${SSH_TARGET}:${HPC_REMOTE_DIR}/${remote_name}" results/ 2>/dev/null || true
done

if ssh_exec test -d "${HPC_REMOTE_DIR}/results"; then
  scp "${SCP_OPTS[@]}" -r "${SSH_TARGET}:${HPC_REMOTE_DIR}/results/." results/ || die "failed to retrieve result directory"
fi

if [[ "${HPC_CLEANUP_ON_SUCCESS:-false}" == "true" ]]; then
  require_var HPC_WORK_ROOT
  validate_absolute_path HPC_WORK_ROOT "$HPC_WORK_ROOT"
  validate_absolute_path HPC_REMOTE_DIR "$HPC_REMOTE_DIR"
  case "$HPC_REMOTE_DIR" in
    "$HPC_WORK_ROOT"/*/*-*) ssh_exec rm -rf -- "$HPC_REMOTE_DIR" ;;
    *) die "refusing cleanup: remote directory does not match expected derived shape" ;;
  esac
fi
log "result retrieval complete"
