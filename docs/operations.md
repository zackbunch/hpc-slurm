# Operations and troubleshooting

## Fast diagnosis

| Symptom | Likely layer | Check |
|---|---|---|
| Timeout before SSH banner | Network/firewall | Runner route, VPN/allowlist, port |
| Host-key verification failed | SSH trust | Compare pinned fingerprint with an HPC site administrator |
| `Permission denied (publickey)` | SSH identity | Public key, account, key format/newline, Vault field |
| `mkdir: Permission denied` | Remote filesystem | `HPC_WORK_ROOT`, ownership, quota |
| `sbatch: command not found` | Login environment | Modules/profile, absolute command path, site docs |
| Job stays `PENDING` | Slurm policy/resources | `squeue -j ID -o '%T %R'`, account/partition/QoS |
| Job exits before simulation | Container/staging | `slurm-ID.err`, `.sif` path, bind policy, execute bit |
| `sacct` returns no row | Accounting delay/config | Wait interval, `scontrol show job`, site policy |
| CI times out but job runs | Cancellation/network | `scancel ID`, then verify with `squeue`/`sacct` |
| Binary loader/library error | ABI/runtime | Build target, architecture, RHEL 8.10 runtime libraries |

## Manual inspection

On the HPC login node:

```bash
squeue -j JOB_ID -o '%i|%T|%R'
scontrol show job JOB_ID
sacct -X -j JOB_ID --noheader --parsable2 --format=JobIDRaw,State,ExitCode
ls -la REMOTE_DIR
sed -n '1,200p' REMOTE_DIR/slurm-JOB_ID.err
```

`sbatch` succeeding only means Slurm accepted the script. It does not mean resources
were allocated or the simulation succeeded.

## Exit behavior

The starter evaluates the allocation record from `sacct -X`, not individual job
steps. It accepts only `State=COMPLETED` and the first component of `ExitCode=0:0`.
Any other terminal state fails CI. Site-specific states with suffixes such as `+`
are normalized before evaluation.

If the HPC site disables `sacct`, adapt `wait_slurm.sh` to use its supported
accounting interface. Do not infer success solely because the job disappeared from
`squeue`.

## Cancellation and cleanup

Run this from a configured CI shell or trusted operator workstation:

```bash
HPC_JOB_ID=12345 scripts/cancel_slurm.sh
```

The full pipeline requests cancellation when its own wait timeout expires. A runner
terminated abruptly cannot execute cleanup, so the HPC site should also enforce Slurm
time limits and a remote-directory retention policy.

Only set `HPC_CLEANUP_ON_SUCCESS=true` after verifying result collection. Failed
runs are intentionally retained for diagnosis. Never aim a recursive cleanup command
at a value that was not derived and validated by these scripts.

## Hardening checklist

- Use a dedicated service account and a dedicated SSH key.
- Restrict source addresses in `authorized_keys` if the runner egress is stable.
- Ask the HPC site administrators whether forced commands or an SSH certificate authority are preferred.
- Use a trusted, protected runner; do not expose HPC credentials to fork pipelines.
- Protect environment/branch access and bind the Vault JWT role to exact claims.
- Pin host keys, the runner image digest, and the approved `.sif` release/digest.
- Keep secrets out of command tracing, artifacts, dotenv reports, and Slurm exports.
- Use Slurm account, partition, QoS, CPU, memory, and wall-time limits.
- Monitor repeated auth failures, abnormal submission volume, stranded jobs, and quota.
- Rotate the SSH key and test revocation on a documented schedule.

## Site adaptations

Some clusters require modules before `apptainer` is available. In that case, add the
site-approved `module load ...` line near the beginning of `slurm/run_sim.slurm`.
Some clusters require a jump host; add ProxyJump only after host keys for every hop
are pinned and the network/security owners approve the route.

For MPI, GPUs, or multi-node execution, do not simply increase `SLURM_TASKS`.
Coordinate the launcher (`srun` versus container-internal MPI), PMI/PMIx version,
GPU passthrough flags, drivers, fabrics, and bind mounts with the HPC site administrators.

