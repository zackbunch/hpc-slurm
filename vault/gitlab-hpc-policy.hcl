# KV v2 data endpoint: allow only the single SSH secret read.
path "kv/data/ci/hpc/ssh" {
  capabilities = ["read"]
}

