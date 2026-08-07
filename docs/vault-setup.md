# Vault-backed SSH credentials

MVP 5 uses GitLab workload identity rather than a stored Vault token:

```text
GitLab ID token → Vault JWT auth → short-lived Vault token → KV v2 SSH key
```

This guide uses illustrative paths. A Vault administrator must adapt and apply the
configuration.

## 1. Store the SSH key

Enable or reuse a KV v2 mount and write the key:

```bash
vault kv put -mount=kv ci/hpc/ssh private_key=@hpc_ci_key
```

The public key is installed on the dedicated HPC service account. The private key should
not have a passphrase because CI is non-interactive; compensate with a dedicated
account, narrow authorization, protected runners/refs, rotation, and audit logging.

## 2. Apply a read-only policy

Review `vault/gitlab-hpc-policy.hcl`, then:

```bash
vault policy write gitlab-hpc vault/gitlab-hpc-policy.hcl
```

KV v2 API reads use the `/data/` path even though `vault kv get` hides that segment.

## 3. Configure JWT authentication

Enable a dedicated mount if one does not already exist:

```bash
vault auth enable -path=jwt jwt
```

For GitLab.com, configure discovery with `https://gitlab.com`. For self-managed
GitLab, use its externally reachable HTTPS URL and trusted CA configuration:

```bash
vault write auth/jwt/config \
  oidc_discovery_url="https://gitlab.example.com" \
  bound_issuer="https://gitlab.example.com"
```

Copy `vault/gitlab-hpc-role.json.example` to a protected working file. Replace:

- `https://vault.example.com` with the exact audience used by the CI job;
- `12345` with the numeric GitLab project ID;
- claim rules if your release branch/tag strategy differs.

Apply it:

```bash
vault write auth/jwt/role/gitlab-hpc @gitlab-hpc-role.json
```

The sample role requires the exact project ID and `ref_protected=true`. Add tighter
bindings such as `ref_type`, `ref`, namespace, or environment where practical. Keep
the token TTL short because it is used only to read the SSH key.

## 4. Configure GitLab variables

Set non-secret variables:

```text
VAULT_ADDR=https://vault.example.com
VAULT_AUTH_PATH=jwt
VAULT_ROLE=gitlab-hpc
VAULT_KV_MOUNT=kv
VAULT_SSH_SECRET_PATH=ci/hpc/ssh
VAULT_SSH_KEY_FIELD=private_key
```

Keep `HPC_SSH_KNOWN_HOSTS` as a GitLab file-type variable. Vault protects the
client credential; it does not replace server host-key verification.

The MVP template declares:

```yaml
id_tokens:
  VAULT_ID_TOKEN:
    aud: $VAULT_ADDR
```

Vault's role `bound_audiences` must exactly match the resulting audience.

## 5. Test negative cases

Before production, verify the role rejects:

- another GitLab project;
- an unprotected branch;
- the wrong audience;
- an expired token;
- a request for any Vault path other than the one policy path.

Check Vault audit logs without logging the ID token, Vault token, or SSH key.

## Native GitLab `secrets:vault` option

Where supported, GitLab can perform the exchange declaratively and expose the secret
as a temporary file. An example job fragment is included as comments in
`.gitlab/ci/mvp-5-vault.yml`. Exact availability depends on GitLab tier, version,
Runner, and secrets-engine support, so validate it against your installation.

The included `vault_fetch_ssh_key.sh` is the transparent HTTP fallback. It uses the
JWT login endpoint and KV v2 data endpoint, keeps the Vault token in memory, writes
the SSH key to a temporary file, and does not print secret values.

