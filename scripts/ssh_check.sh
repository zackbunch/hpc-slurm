#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

"${SCRIPT_DIR}/setup_ssh.sh"
load_ssh_options

log "checking SSH connectivity to ${HPC_HOST}:${HPC_SSH_PORT}"
ssh_exec bash -lc 'printf "remote_user=%s\nremote_host=%s\n" "$(id -un)" "$(hostname)"'

required_commands="${HPC_PREFLIGHT_COMMANDS:-}"
if [[ -n "$required_commands" ]]; then
  [[ "$required_commands" =~ ^[A-Za-z0-9._[:space:]-]+$ ]] || die "HPC_PREFLIGHT_COMMANDS contains unsupported characters"
  ssh_exec bash -lc "for c in ${required_commands}; do command -v \"\$c\" >/dev/null || { echo \"missing_command=\$c\" >&2; exit 20; }; done"
  log "required remote commands are available: ${required_commands}"
fi
log "SSH connectivity succeeded"
