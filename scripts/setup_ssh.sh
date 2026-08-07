#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_var HPC_SSH_PRIVATE_KEY
require_var HPC_SSH_KNOWN_HOSTS

umask 077
mkdir -p "$SSH_DIR"

copy_variable_to_file() {
  local source_value="$1" destination="$2"
  if [[ -f "$source_value" ]]; then
    if [[ "$source_value" != "$destination" ]]; then
      cp "$source_value" "$destination"
    fi
  else
    printf '%s\n' "$source_value" >"$destination"
  fi
}

copy_variable_to_file "$HPC_SSH_PRIVATE_KEY" "$SSH_KEY_PATH"
copy_variable_to_file "$HPC_SSH_KNOWN_HOSTS" "$SSH_KNOWN_HOSTS_PATH"
chmod 600 "$SSH_KEY_PATH"
chmod 644 "$SSH_KNOWN_HOSTS_PATH"

ssh-keygen -y -f "$SSH_KEY_PATH" >/dev/null 2>&1 || die "SSH private key is unreadable or requires a passphrase"
[[ -s "$SSH_KNOWN_HOSTS_PATH" ]] || die "known_hosts file is empty"
log "SSH client material prepared without printing credentials"

