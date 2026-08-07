# Architecture

## Runtime path

```mermaid
flowchart LR
    subgraph GL["GitLab network"]
        Repo["Git repository"]
        Runner["GitLab runner"]
        Artifacts["GitLab job artifacts"]
        Repo -->|"pipeline checkout"| Runner
        Runner -->|"results and logs"| Artifacts
    end

    subgraph HPC["HPC network"]
        Login["Login / submission node"]
        Slurm["Slurm controller"]
        Compute["Allocated compute node"]
        Work["Per-pipeline work directory"]
        Image["Approved RHEL 8.10 .sif"]

        Login -->|"sbatch"| Slurm
        Slurm -->|"allocates and launches"| Compute
        Compute -->|"reads binary; writes results"| Work
        Compute -->|"apptainer exec"| Image
    end

    Runner -->|"SSH: check, submit, poll"| Login
    Runner -->|"SCP: sim + Slurm script"| Work
    Work -->|"SCP: logs + result bundle"| Runner
```

The runner never SSHes to a compute node. It uses the login node only for file
staging and Slurm commands. Slurm decides where and when the simulation runs.

## Credential path for MVP 5

```mermaid
sequenceDiagram
    autonumber
    participant G as GitLab job
    participant V as Vault
    participant C as HPC login node
    participant S as Slurm
    participant N as Compute node

    G->>G: Receive job-scoped OIDC ID token
    G->>V: JWT login with audience and bound claims
    V-->>G: Short-lived, policy-scoped Vault token
    G->>V: Read SSH private key from KV v2
    V-->>G: Key held in temporary job file
    G->>C: SSH with pinned host key
    G->>C: Upload binary and Slurm script
    G->>C: Submit job
    C->>S: sbatch
    S->>N: Allocate and launch
    N->>N: apptainer exec approved .sif ./sim
    G->>C: Poll squeue / sacct
    G->>C: Retrieve logs and results
    G->>G: Remove temporary key on job exit
```

## Components and ownership

| Component | Suggested owner | Change frequency | Approval boundary |
|---|---|---:|---|
| Simulation source/binary | Application team | Frequent | Normal code review |
| Runtime OCI image (RHEL 8.10) | Runtime/image team | Occasional | Image scan and site conversion review |
| Approved `.sif` | HPC site administrators | Rare | Site approval; immutable path or digest |
| Slurm job settings | Application + HPC platform teams | Occasional | Queue/account/site policy |
| SSH account and authorized key | HPC site administrators | Rotated | Least privilege and audit policy |
| Vault JWT role/policy | Security/Vault administrators | Rare | Bound project/ref/audience claims |
| GitLab pipeline | Application/CI team | Frequent | Protected branches and CI review |

## Trust boundaries

1. **GitLab runner boundary.** The runner receives source, the binary, and a
   temporary credential. Use a trusted runner; avoid shared untrusted runners.
2. **SSH boundary.** Pin the HPC login-node host key. The runner does not learn
   host keys dynamically during a job.
3. **Login-node boundary.** The SSH account can stage files and submit only its own
   Slurm jobs. It should not have administrative privileges.
4. **Scheduler boundary.** Resource policy is enforced by Slurm. CI does not pick
   a compute-node hostname.
5. **Container boundary.** The `.sif` is an approved runtime artifact, not a general
   security sandbox. Site policy controls mounts, devices, and execution.

## Data lifecycle

```mermaid
stateDiagram-v2
    [*] --> Built: GitLab creates build/sim
    Built --> Staged: SCP to isolated remote directory
    Staged --> Queued: sbatch returns job ID
    Queued --> Running: Slurm allocates resources
    Running --> Finished: simulation exits
    Finished --> Collected: logs/results copied to GitLab
    Collected --> Retained: GitLab artifact policy
    Collected --> Cleaned: optional remote cleanup
    Queued --> Cancelled: operator or timeout scancel
    Running --> Cancelled: operator or timeout scancel
```

Keep remote runs until results are safely collected. Apply a separate,
administrator-approved retention process to abandoned directories.

