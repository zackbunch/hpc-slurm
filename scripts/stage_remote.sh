#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd jq
SIM_LOCAL_PATH="${SIM_LOCAL_PATH:-build/sim}"
SLURM_SCRIPT_LOCAL_PATH="${SLURM_SCRIPT_LOCAL_PATH:-slurm/run_sim.slurm}"
[[ -f "$SIM_LOCAL_PATH" ]] || die "simulation binary not found: $SIM_LOCAL_PATH"
[[ -f "$SLURM_SCRIPT_LOCAL_PATH" ]] || die "Slurm script not found: $SLURM_SCRIPT_LOCAL_PATH"

"${SCRIPT_DIR}/setup_ssh.sh"
load_ssh_options
derive_remote_dir

require_var HPC_CONTAINER
validate_absolute_path HPC_CONTAINER "$HPC_CONTAINER"
APPTAINER_EXTRA_BINDS="${APPTAINER_EXTRA_BINDS:-}"
[[ "$APPTAINER_EXTRA_BINDS" =~ ^[A-Za-z0-9_./,:=-]*$ ]] || die "APPTAINER_EXTRA_BINDS contains unsupported characters"
SIM_ARGS="${SIM_ARGS:-[] }"
jq -e 'type == "array" and all(.[]; type == "string")' <<<"$SIM_ARGS" >/dev/null || die "SIM_ARGS must be a JSON array of strings"

local_tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$local_tmp_dir"' EXIT
{
  printf 'HPC_CONTAINER=%q\n' "$HPC_CONTAINER"
  printf 'APPTAINER_EXTRA_BINDS=%q\n' "$APPTAINER_EXTRA_BINDS"
} >"${local_tmp_dir}/job.env"
jq -r '.[] | @base64' <<<"$SIM_ARGS" >"${local_tmp_dir}/sim.args.b64"

log "creating isolated remote directory: ${HPC_REMOTE_DIR}"
ssh_exec mkdir -p -- "$HPC_REMOTE_DIR"
ssh_exec chmod 700 -- "$HPC_REMOTE_DIR"

scp "${SCP_OPTS[@]}" \
  "$SIM_LOCAL_PATH" \
  "$SLURM_SCRIPT_LOCAL_PATH" \
  "${local_tmp_dir}/job.env" \
  "${local_tmp_dir}/sim.args.b64" \
  "${SSH_TARGET}:${HPC_REMOTE_DIR}/"

ssh_exec chmod 700 -- "${HPC_REMOTE_DIR}/sim"
ssh_exec chmod 600 -- "${HPC_REMOTE_DIR}/job.env" "${HPC_REMOTE_DIR}/sim.args.b64"
ssh_exec chmod 700 -- "${HPC_REMOTE_DIR}/run_sim.slurm"

printf 'HPC_REMOTE_DIR=%s\n' "$HPC_REMOTE_DIR" >remote.env
log "staged simulation and Slurm files"

