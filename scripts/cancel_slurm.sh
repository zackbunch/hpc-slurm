#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

"${SCRIPT_DIR}/setup_ssh.sh"
load_ssh_options
require_var HPC_JOB_ID
[[ "$HPC_JOB_ID" =~ ^[0-9]+$ ]] || die "HPC_JOB_ID must be numeric"
slurm_cluster_args
ssh_exec scancel "${SLURM_CLUSTER_ARGS[@]}" "$HPC_JOB_ID"
log "cancellation requested for Slurm job ${HPC_JOB_ID}"

