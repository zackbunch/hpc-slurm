#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd curl
require_cmd jq
for name in VAULT_ADDR VAULT_AUTH_PATH VAULT_ROLE VAULT_KV_MOUNT VAULT_SSH_SECRET_PATH VAULT_SSH_KEY_FIELD VAULT_ID_TOKEN; do
  require_var "$name"
done
[[ "$VAULT_ADDR" =~ ^https://[A-Za-z0-9._:-]+$ ]] || die "VAULT_ADDR must be a simple HTTPS origin"
[[ "$VAULT_AUTH_PATH" =~ ^[A-Za-z0-9_/-]+$ ]] || die "invalid VAULT_AUTH_PATH"
[[ "$VAULT_KV_MOUNT" =~ ^[A-Za-z0-9_/-]+$ ]] || die "invalid VAULT_KV_MOUNT"
[[ "$VAULT_SSH_SECRET_PATH" =~ ^[A-Za-z0-9_./-]+$ ]] || die "invalid VAULT_SSH_SECRET_PATH"
validate_simple_name VAULT_ROLE "$VAULT_ROLE"
validate_simple_name VAULT_SSH_KEY_FIELD "$VAULT_SSH_KEY_FIELD"

secrets_dir="${PROJECT_DIR}/.secrets"
key_path="${secrets_dir}/hpc_key"
response_file="$(mktemp)"
trap 'rm -f -- "$response_file"' EXIT
umask 077
mkdir -p "$secrets_dir"

login_payload="$(jq -n --arg role "$VAULT_ROLE" --arg jwt "$VAULT_ID_TOKEN" '{role:$role,jwt:$jwt}')"
http_code="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
  --request POST --header 'Content-Type: application/json' --data "$login_payload" \
  "${VAULT_ADDR}/v1/auth/${VAULT_AUTH_PATH}/login")"
[[ "$http_code" == "200" ]] || die "Vault JWT login failed with HTTP ${http_code}"
vault_token="$(jq -er '.auth.client_token' "$response_file")" || die "Vault login response did not contain a client token"

http_code="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
  --header "X-Vault-Token: ${vault_token}" \
  "${VAULT_ADDR}/v1/${VAULT_KV_MOUNT}/data/${VAULT_SSH_SECRET_PATH}")"
unset vault_token VAULT_ID_TOKEN login_payload
[[ "$http_code" == "200" ]] || die "Vault secret read failed with HTTP ${http_code}"

jq -er --arg field "$VAULT_SSH_KEY_FIELD" '.data.data[$field]' "$response_file" >"$key_path" || die "Vault secret field was not found"
printf '\n' >>"$key_path"
chmod 600 "$key_path"
ssh-keygen -y -f "$key_path" >/dev/null 2>&1 || die "Vault value is not a usable unencrypted SSH private key"
printf '%s\n' "$key_path"

