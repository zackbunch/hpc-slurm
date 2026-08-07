# GitLab → HPC starter

This repository is a configurable starting point for this execution path:

```text
GitLab runner → SSH/SCP → HPC login node → Slurm → Apptainer → simulation
```

It assumes your team already builds a runtime image from Red Hat Enterprise Linux
8.10 and that the HPC site approves and installs the converted Apptainer `.sif` image.
The normal pipeline does **not** copy or rebuild that image. It transfers the
frequently changing simulation binary, submits a Slurm job, waits for completion,
and brings the results back to GitLab.

Start with one MVP at a time. Do not begin with the full pipeline.

## Repository map

```text
.
├── .gitlab-ci.yml                 # Complete starter pipeline (MVP 1–4)
├── .gitlab/ci/
│   ├── mvp-1-ssh.yml              # Connectivity only
│   ├── mvp-2-scp.yml              # Build + transfer
│   ├── mvp-3-slurm.yml            # Submit without waiting
│   ├── mvp-4-results.yml          # Submit, poll, retrieve, pass/fail
│   └── mvp-5-vault.yml            # Same run with a Vault-sourced key
├── config/hpc.env.example         # Site-specific values
├── docs/
│   ├── architecture.md            # Mermaid diagrams and trust boundaries
│   ├── image-approval.md          # OCI-to-SIF handoff and approval checklist
│   ├── implementation.md          # Detailed setup and MVP runbook
│   ├── operations.md              # Troubleshooting and production hardening
│   ├── references.md              # Primary documentation links
│   └── vault-setup.md             # GitLab OIDC → Vault setup
├── examples/sim                   # Tiny executable used for initial validation
├── scripts/
│   ├── common.sh                  # Validation and SSH helpers
│   ├── setup_ssh.sh               # Key/known-host setup
│   ├── ssh_check.sh               # MVP 1
│   ├── stage_remote.sh            # MVP 2
│   ├── submit_slurm.sh            # MVP 3
│   ├── wait_slurm.sh              # MVP 4 polling and exit mapping
│   ├── retrieve_results.sh        # MVP 4 download
│   ├── cancel_slurm.sh            # Best-effort cancellation
│   └── vault_fetch_ssh_key.sh      # MVP 5 JWT login and KV read
├── slurm/run_sim.slurm            # Runs the staged binary in Apptainer
└── vault/                          # Example least-privilege policy and role
```

## Prerequisites

- A GitLab runner with network access to the HPC login node.
- `bash`, `openssh-client`, `curl`, and `jq` in the runner image.
- A dedicated non-interactive HPC account (recommended) with:
  - SSH public-key authentication;
  - permission to write below `HPC_WORK_ROOT`;
  - permission to submit and inspect its own Slurm jobs;
  - permission to read/execute the approved `.sif` image.
- `sbatch`, `squeue`, `sacct`, `scancel`, and `apptainer` on the HPC system.
- A simulation binary compatible with the RHEL 8.10 userspace in the approved image.

Confirm with the HPC site administrators: login hostname, SSH port, work root,
Slurm account/partition/QoS, job limits, Apptainer path, bind-mount policy,
approved image path/digest, outbound-network policy, and result-retention rules.

## Quick start: MVP 1

1. Copy `.gitlab/ci/mvp-1-ssh.yml` to `.gitlab-ci.yml` on a test branch.
2. Add these GitLab CI/CD variables:

   | Variable | Type | Example | Notes |
   |---|---|---|---|
   | `HPC_HOST` | Variable | `login.hpc.example` | Login node, never a compute node |
   | `HPC_USER` | Variable | `gitlab_sim` | Dedicated account preferred |
   | `HPC_SSH_PRIVATE_KEY` | File | private key content | End the value with a newline |
   | `HPC_SSH_KNOWN_HOSTS` | File | pinned host-key line | Obtain through a trusted channel |
   | `HPC_SSH_PORT` | Variable | `22` | Optional; defaults to 22 |

3. Protect the key and limit it to protected branches/environments as appropriate.
4. Run the manual `hpc:ssh-check` job.
5. Progress through the templates in numeric order, copying one template to the
   repository root each time.

MVP 1 tests SSH identity only. Set `HPC_PREFLIGHT_COMMANDS` to a space-separated
list such as `sbatch squeue sacct scancel` when you are ready to validate tools on
the login node. Apptainer itself may be available only inside scheduled jobs.

Never run `ssh-keyscan` inside CI. Pin the login node key obtained from the HPC
site administrators or from a trusted network.

## Full pipeline

After MVP 4 succeeds, restore the included `.gitlab-ci.yml`. Its flow is:

1. `build:sim` stages the demo executable. Replace this job with your real build.
2. `hpc:ssh-check` confirms the login node and required HPC commands.
3. `hpc:stage` creates an isolated remote directory and uploads the binary and job script.
4. `hpc:submit` submits the job and records the job ID and remote directory.
5. `hpc:collect` polls Slurm, downloads results/logs, and exits with the simulation's status.

The final job always attempts to download diagnostic files. If CI is canceled,
use the printed job ID with `scripts/cancel_slurm.sh`, or add site-approved cleanup
automation after validating behavior with the HPC site administrators.

## Configuration

GitLab variables override defaults in `.gitlab-ci.yml`. The complete list and
example values are in `config/hpc.env.example`. Important values are:

- `HPC_WORK_ROOT`: remote base directory, such as `/project/team/gitlab-runs`.
- `HPC_CONTAINER`: absolute path to the approved `.sif` on the HPC system.
- `SLURM_ACCOUNT`, `SLURM_PARTITION`, `SLURM_QOS`: site allocation settings.
- `SLURM_TIME`, `SLURM_CPUS`, `SLURM_MEMORY`: resource request.
- `SLURM_POLL_SECONDS`, `SLURM_WAIT_TIMEOUT_SECONDS`: CI polling behavior.
- `SIM_ARGS`: optional arguments, encoded as a JSON array for safe parsing.
- `APPTAINER_EXTRA_BINDS`: optional comma-separated bind specifications.

The remote directory is derived as:

```text
$HPC_WORK_ROOT/$CI_PROJECT_PATH_SLUG/$CI_PIPELINE_ID-$CI_JOB_ID
```

The scripts reject unsafe path characters before using that value.

## Replace the demo binary

Change `build:sim` so its artifact is a Linux executable at `build/sim`. Build it
against the ABI and libraries expected by your approved RHEL 8.10-derived image.
For dynamic binaries, check `file build/sim` and `ldd build/sim` during the build,
but remember that the authoritative test is execution inside the approved `.sif`.

## Vault-backed credentials

MVP 5 exchanges a GitLab job ID token for a short-lived Vault token, then reads an
SSH private key from Vault KV v2. No long-lived Vault token is stored in GitLab.
See `docs/vault-setup.md` and `.gitlab/ci/mvp-5-vault.yml`.

If your GitLab tier and Runner support native `secrets:vault`, prefer the
declarative example in the Vault guide. The included shell fallback works with
the Vault HTTP API and makes every exchange visible for initial integration.

## Next reading

- `docs/architecture.md` — architecture and trust boundaries.
- `docs/image-approval.md` — controlled RHEL 8.10 OCI-to-SIF promotion.
- `docs/implementation.md` — exact implementation sequence and acceptance checks.
- `docs/operations.md` — failure modes, cleanup, and hardening.
- `docs/vault-setup.md` — Vault operator and GitLab configuration.
- `docs/references.md` — official GitLab, Vault, Slurm, and Apptainer sources.
