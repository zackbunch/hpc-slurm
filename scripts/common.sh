#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="${CI_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SSH_DIR="${PROJECT_DIR}/.ssh"
SSH_KEY_PATH="${SSH_DIR}/hpc_key"
SSH_KNOWN_HOSTS_PATH="${SSH_DIR}/known_hosts"

log() {
  printf '[hpc-ci] %s\n' "$*"
}

die() {
  printf '[hpc-ci] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_var() {
  local name="$1"
  [[ -n "${!name:-}" ]] || die "required variable is empty: ${name}"
}

validate_simple_name() {
  local name="$1" value="$2"
  [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]] || die "${name} contains unsupported characters"
}

validate_absolute_path() {
  local name="$1" value="$2"
  [[ "$value" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "${name} must be an absolute path using only letters, digits, /, ., _, and -"
  [[ "$value" != "/" ]] || die "${name} must not be /"
  [[ "$value" != *"//"* && "$value" != *"/../"* && "$value" != */.. && "$value" != *"/./"* ]] || die "${name} contains unsafe path segments"
}

validate_connection() {
  require_var HPC_HOST
  require_var HPC_USER
  HPC_SSH_PORT="${HPC_SSH_PORT:-22}"
  [[ "$HPC_HOST" =~ ^[A-Za-z0-9.-]+$ ]] || die "HPC_HOST contains unsupported characters"
  validate_simple_name HPC_USER "$HPC_USER"
  [[ "$HPC_SSH_PORT" =~ ^[0-9]+$ ]] || die "HPC_SSH_PORT must be numeric"
}

load_ssh_options() {
  validate_connection
  [[ -r "$SSH_KEY_PATH" ]] || die "SSH key is not prepared; run scripts/setup_ssh.sh first"
  [[ -r "$SSH_KNOWN_HOSTS_PATH" ]] || die "known_hosts is not prepared; run scripts/setup_ssh.sh first"

  SSH_OPTS=(
    -F /dev/null
    -p "$HPC_SSH_PORT"
    -i "$SSH_KEY_PATH"
    -o BatchMode=yes
    -o IdentitiesOnly=yes
    -o StrictHostKeyChecking=yes
    -o "UserKnownHostsFile=$SSH_KNOWN_HOSTS_PATH"
    -o ConnectTimeout=20
    -o ServerAliveInterval=30
    -o ServerAliveCountMax=3
  )
  SCP_OPTS=(
    -F /dev/null
    -P "$HPC_SSH_PORT"
    -i "$SSH_KEY_PATH"
    -o BatchMode=yes
    -o IdentitiesOnly=yes
    -o StrictHostKeyChecking=yes
    -o "UserKnownHostsFile=$SSH_KNOWN_HOSTS_PATH"
    -o ConnectTimeout=20
  )
  SSH_TARGET="${HPC_USER}@${HPC_HOST}"
}

ssh_exec() {
  local command_string='' quoted arg
  for arg in "$@"; do
    printf -v quoted '%q' "$arg"
    command_string+="${command_string:+ }${quoted}"
  done
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "$command_string"
}

derive_remote_dir() {
  require_var HPC_WORK_ROOT
  validate_absolute_path HPC_WORK_ROOT "$HPC_WORK_ROOT"
  local project_slug="${CI_PROJECT_PATH_SLUG:-local-project}"
  local pipeline_id="${CI_PIPELINE_ID:-local}"
  local job_id="${CI_JOB_ID:-manual}"
  validate_simple_name CI_PROJECT_PATH_SLUG "$project_slug"
  validate_simple_name CI_PIPELINE_ID "$pipeline_id"
  validate_simple_name CI_JOB_ID "$job_id"
  HPC_REMOTE_DIR="${HPC_WORK_ROOT}/${project_slug}/${pipeline_id}-${job_id}"
  validate_absolute_path HPC_REMOTE_DIR "$HPC_REMOTE_DIR"
  export HPC_REMOTE_DIR
}

load_remote_env() {
  local env_file="${1:-remote.env}"
  [[ -r "$env_file" ]] || die "missing ${env_file} artifact"
  # shellcheck disable=SC1090
  source "$env_file"
  require_var HPC_REMOTE_DIR
  validate_absolute_path HPC_REMOTE_DIR "$HPC_REMOTE_DIR"
}

slurm_cluster_args() {
  SLURM_CLUSTER_ARGS=()
  if [[ -n "${SLURM_CLUSTER:-}" ]]; then
    validate_simple_name SLURM_CLUSTER "$SLURM_CLUSTER"
    SLURM_CLUSTER_ARGS=(--clusters "$SLURM_CLUSTER")
  fi
}

