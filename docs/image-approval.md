# RHEL 8.10 runtime image handoff

The existing runtime OCI image and the approved HPC `.sif` are two forms of one
versioned runtime release. Treat conversion as a controlled promotion process, not
as an incidental step in every simulation pipeline.

## Recommended handoff

1. Build the RHEL 8.10-based OCI image in the normal trusted image pipeline.
2. Scan it and push it to an approved registry under an immutable digest.
3. Give the HPC site administrators the digest, Dockerfile/build provenance, SBOM,
   scan result, intended mounts/devices, entrypoint behavior, and runtime owner.
4. Convert on a controlled builder using the Apptainer version and policy approved
   by the HPC site. Prefer pulling by digest, for example:

   ```bash
   apptainer build --reproducible hpc-rhel8.10-1.0.0.sif \
     docker://registry.example.com/team/hpc@sha256:CHANGE_ME
   ```

5. Hash and inspect the output:

   ```bash
   sha256sum hpc-rhel8.10-1.0.0.sif
   apptainer inspect hpc-rhel8.10-1.0.0.sif
   apptainer exec hpc-rhel8.10-1.0.0.sif cat /etc/redhat-release
   ```

6. Run the site's security/compatibility review and a scheduled smoke job.
7. Install the approved file at a versioned, read-only location such as
   `/approved/containers/hpc-rhel8.10-1.0.0.sif`.
8. Update `HPC_CONTAINER` only through reviewed configuration. Never silently
   replace the bytes behind an approved versioned path.

The exact build command is illustrative. Private-registry authentication, signing,
encryption, fakeroot/user namespaces, supported squashfs compression, and permitted
bootstrap sources are site policy decisions.

## Approval record

Record at minimum:

| Field | Example |
|---|---|
| Runtime release | `hpc-rhel8.10-1.0.0` |
| Source repository/commit | immutable commit SHA |
| OCI reference | registry path plus `sha256:` digest |
| Base release | RHEL 8.10 |
| SBOM/scan | artifact URL and result |
| Builder | controlled host/service and Apptainer version |
| SIF SHA-256 | checksum of approved file |
| HPC system path | versioned absolute path |
| Required binds/devices | explicit list |
| Smoke test | job ID and result |
| Approval | owner, ticket, date, expiration |

## Compatibility tests

Test more than `/etc/redhat-release`. Exercise the dynamic loader, CPU architecture,
critical runtime libraries, licenses, MPI/GPU stack if applicable, filesystem binds,
working directory, locale, and representative simulation input. The MVP 4 pipeline
then verifies the changing binary against the already approved runtime.

