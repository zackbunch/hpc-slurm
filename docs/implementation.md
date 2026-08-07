# Implementation guide

This runbook deliberately grows one capability at a time. Each MVP has a narrow
acceptance check so failures are easy to locate.

## Phase 0 — decisions and approvals

Before changing CI, record these answers with the HPC site administrators:

- Which login node, port, and host-key fingerprints should CI trust?
- Is the GitLab runner network allowed to reach that endpoint?
- Which service account, Slurm account, partition, and QoS should be used?
- Where may CI create run directories, and what quota/retention applies?
- What is the immutable path (or release-specific path) of the approved `.sif`?
- Does the site permit user bind mounts and the requested work filesystem?
- Is `sacct` accounting enabled and how quickly do completed jobs appear?
- Which states and preemption/requeue behaviors are normal at the site?
- What input/output data may cross the network boundary?

Convert the RHEL 8.10 OCI image to Apptainer using the process approved by the
HPC site. Do not add image conversion to the per-commit pipeline unless the site
explicitly requires and approves it. Record the OCI digest, `.sif` digest, scanner result,
approval ticket, owner, and expiration date.

## MVP 1 — SSH connectivity

Use `.gitlab/ci/mvp-1-ssh.yml` as the root pipeline.

Configure `HPC_HOST`, `HPC_USER`, and optionally `HPC_SSH_PORT` as normal
variables. Configure the following as GitLab **file-type** variables:

- `HPC_SSH_PRIVATE_KEY`: a dedicated key whose public half is authorized on the HPC login node.
- `HPC_SSH_KNOWN_HOSTS`: the login-node host key obtained through a trusted channel.

The job uses `BatchMode=yes` and `StrictHostKeyChecking=yes`; it cannot prompt or
silently accept a new host key. It checks identity and hostname. Once that works,
set `HPC_PREFLIGHT_COMMANDS="sbatch squeue sacct scancel"` to validate the Slurm
client commands on the login node. Apptainer may be exposed only in scheduled jobs.

Acceptance criteria:

- The manual job connects without a prompt.
- The reported remote user is the expected dedicated account.
- Any commands named in `HPC_PREFLIGHT_COMMANDS` are found.
- A changed or missing host key causes a hard failure.

## MVP 2 — SCP artifact transfer

Use `.gitlab/ci/mvp-2-scp.yml`. Initially, `examples/sim` is copied to
`build/sim`; replace that command with your real compiler/build system later.

The staging script validates the configured paths, creates a unique directory,
uploads the binary and `slurm/run_sim.slurm`, sets restrictive permissions, and
writes `remote.env` as a GitLab dotenv artifact.

Acceptance criteria:

- The remote directory is below `HPC_WORK_ROOT`.
- Two files exist there: executable `sim` and readable `run_sim.slurm`.
- Concurrent pipelines produce different directories.
- The dotenv artifact contains `HPC_REMOTE_DIR`, never a secret.

## MVP 3 — Slurm submission

Use `.gitlab/ci/mvp-3-slurm.yml`. `submit_slurm.sh` supplies resources as `sbatch`
arguments rather than trying to interpolate variables in `#SBATCH` lines.

Slurm returns a parseable job ID, saved in `job.env`. Inspect it on the HPC system:

```bash
squeue -j JOB_ID
scontrol show job JOB_ID
```

Acceptance criteria:

- Submission returns a numeric job ID (federated clusters may append a cluster name).
- `scontrol show job` points to the unique staged directory.
- The job invokes the site-approved `.sif`, not a transferred image.
- Output appears as `slurm-JOB_ID.out` and `slurm-JOB_ID.err` in the run directory.

## MVP 4 — polling, exit status, and results

Use `.gitlab/ci/mvp-4-results.yml` or the complete root `.gitlab-ci.yml`.

The wait script:

1. polls `squeue` while the job is pending/running;
2. switches to `sacct` for the terminal state and `ExitCode`;
3. enforces a CI-side timeout and requests `scancel` on timeout;
4. maps `COMPLETED` plus exit code zero to CI success;
5. treats failed, canceled, timed-out, out-of-memory, and unknown outcomes as failure.

The collect job downloads files even after the wait step fails, then returns the
original status. GitLab retains `results/` using `artifacts:when: always`.

Acceptance criteria:

- A successful simulation makes GitLab green and returns logs/results.
- A deliberate nonzero simulation exit makes GitLab red and still returns logs.
- A short test timeout cancels the Slurm job and makes GitLab red.
- A pending job is not mistaken for a submission failure.

## MVP 5 — Vault-backed SSH credential

Follow `docs/vault-setup.md`, then use `.gitlab/ci/mvp-5-vault.yml`.

The job asks GitLab for an ID token whose audience is exactly `VAULT_ADDR`. Vault
validates its issuer/signature/audience and bound GitLab claims, returns a
short-lived token, and allows one KV v2 read. The SSH key is written to a temporary
file, loaded into `ssh-agent`, and removed by the job cleanup trap.

Acceptance criteria:

- No static Vault token exists in GitLab variables.
- The Vault role rejects a different project and an unprotected ref.
- The Vault token TTL is only long enough for key retrieval.
- The key never appears in logs or artifacts.
- Rotating the Vault secret requires no pipeline-file change.

## Production transition

After all MVPs pass:

- Pin the CI tool image by digest and host it in your approved registry.
- Replace the demo build with the real build and keep its artifact interface (`build/sim`).
- Pin the approved `.sif` by versioned path and record its SHA-256 digest.
- Add branch/environment rules so only authorized refs can reach the HPC environment.
- Set appropriate GitLab artifact expiration and remote HPC retention.
- Run failure tests for nonzero exit, OOM, timeout, cancellation, bad host key,
  unavailable accounting, quota exhaustion, and a temporarily unavailable login node.
- Decide who may cancel jobs and who responds to stranded jobs/directories.
