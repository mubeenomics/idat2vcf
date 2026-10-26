# Validation status

Local checks performed on 2026-10-26. This section reflects the current validated
state; later sections retain the dated history of intermediate rounds.

## Current state

- Bash syntax checks and ShellCheck 0.11.0 pass for the pipeline, test fixture,
  and bundled first-party logger, with sourced-library analysis enabled (`-x`).
- **Twenty-one** standard-library unittest cases pass. Coverage includes failures
  at each conversion stage, failed-intermediate preservation, cleanup, output
  protection, lock handling, missing resources, empty input, invalid arguments,
  help output, filtered log events, JSON event context, duplicate file-sink
  prevention, invalid logger configuration, logger/tee/lock-cleanup failures
  without masking tool exit codes, quiet/verbose console modes, banner suppression,
  captured DEBUG details, `HOST_LOG_DIR` overrides (spaces, trailing slash,
  non-absolute rejection), completion-event capture for all three logger routing
  modes, and prompt SIGTERM interruption.
- Final image `idat2vcf:local`:
  `sha256:4124fff72e24dc4921130244db8eb598c87371417a3dd1b8d20857ead465021b`
  (4,358,787,444 bytes), including logshuru v2.0.0. Installed bcftools is
  **1.20** (package build `h8b25389_1`) running against **htslib 1.24**, on the
  pinned Miniforge base `condaforge/miniforge3:26.9.4-0` (Ubuntu 24.04.5 LTS,
  conda 26.9.4, mamba 2.9.0). The pinned plugins remain gtc2vcf 1.20-20240927.
- Real-data quiet and verbose runs with per-project logs
  (`<project>/logs/idat2vcf/`, explicit `HOST_LOG_DIR`) at
  `/tmp/opencode/idat2vcf-projectlogs-9n38dxfa` matched the established baseline:
  three sample IDs, 653,817 sorted/indexed records, identical canonical digest,
  217-record indexed regional query, baseline call rates, full cleanup, and
  status summaries printing the explicit host log path. Private report:
  `data/console-cleanup-validation.json`.
- A real `docker stop` during conversion (at
  `/tmp/opencode/idat2vcf-stop-mi1qh_6s`) exited 143 with a `Terminated` warning,
  retained intermediates, released the lock, logged the failure summary, and kept
  the full log. Private report: `data/interruption-validation.json`.
- Earlier detailed rounds (Docker repair, first integration, logger integration,
  invocation modes, console cleanup) are documented below and remain accurate as
  history, though test/image references inside them reflect those earlier rounds.

## Passed (historical detail)

- Bash syntax checks for `idat2vcf.docker.sh` and the test bcftools fixture.
- ShellCheck 0.11.0 for the pipeline, test fixture, and bundled first-party logger, with
  sourced-library analysis enabled (`-x`).
- Seventeen standard-library unittest cases, including failures at each of the four
  conversion stages, preservation of failed intermediates, successful cleanup,
  repeated-run output protection, existing lock ownership, missing resources,
  empty input, invalid arguments, and help output. Additional checks cover filtered
  log events, JSON event context, duplicate file-sink prevention, invalid logger
  configuration, and preservation of exit code 42 plus cleanup when logging fails.
  Console-mode checks cover quiet/verbose output, final-summary ordering, capture
  failure, cleanup failure, and preserving a tool error when either also fails.
- SHA-256 inventory of all seven files inside the supplied archive.
- Both plugin checksums match Broad's `gtc2vcf_1.20-20240927.zip` release.
- All 195 FASTA index entries match sequence names, lengths, byte offsets, and
  line widths recomputed from the supplied FASTA.
- All 654,027 CSV assay records specify genome build 38; the CSV descriptor
  matches the supplied BPM filename. BPM and EGT headers identify GSA v3.0.
- Git ignore rule excludes the local resource TAR; Python caches are excluded.
- Docker image build completed with BuildKit using Docker Engine 28.3.3 and
  Buildx 0.25.0. All seven build-time resource checksum checks passed.
- Image `idat2vcf:local`:
  `sha256:a3c41f2709878eff2ff151b8d09af12c8ba63ad6bc796a9ff10251a3d7bf5ece`
  (4,264,153,066 bytes), including logshuru v2.0.0. Installed bcftools is 1.20 with
  HTSlib 1.22.1. The original pre-logger integration image was
  `sha256:2b266ad69552245eb7b4ceae8ef7d2d1dabe9095227648b2b796df7691153857`.
- Container default help/entrypoint, plugin discovery, and both plugin help
  commands passed. The build-mounted TAR is absent from the final filesystem;
  third-party notices are present.
- A real manifest-only conversion loaded the BPM, CSV, EGT, and FASTA together,
  then sorted, normalized, and indexed the output. gtc2vcf reported 654,027 input
  loci, 0 missing-reference loci, and 210 skipped loci. Normalization processed
  653,817 records, realigned 1,337, and skipped 0 for reference mismatch. The BCF
  index reports 653,817 records. This does not exercise IDAT genotype calling.
- An actual container run with empty mounted inputs passed prerequisite/plugin
  checks and failed clearly with `No IDAT files found`. It wrote a host-user-owned
  log and released its project lock.
- Verified rootless mount behavior: the default container root user can write to
  host-user-owned mounts; passing `--user 5252:5252` cannot. README instructions
  now distinguish rootless from rootful Docker.

## Real IDAT integration test (2026-10-26)

- Renamed six supplied IDAT files into three pairs:
  `SAMPLE001_{Grn,Red}.idat`, `SAMPLE002_{Grn,Red}.idat`, and
  `SAMPLE003_{Grn,Red}.idat`. SHA-256 checksums verified that renaming did not
  change any binary contents. Original filenames are not recorded here.
- Ran the actual container pipeline with rootless Docker, persistent data/log
  mounts, and a read-only mount of the renamed input directory.
- Project `TEST_INITIAL` completed IDAT → GTC → VCF, producing three GTCs followed
  by `data/TEST_INITIAL.vcf.gz`, its CSI index, and `.extra.tsv` metadata. Successful
  cleanup removed the run-owned intermediates and lock.
- The VCF contains exactly the three expected sample IDs and **653,817** records.
  Fully decoded the compressed VCF, checked every record's sample-column count
  and coordinate order, and confirmed the full-stream count equals the CSI count.
- An index-backed query of `chr1:1000000-2000000` returned 217 records.
- All metadata rows match the anonymous GTC filenames. GTC call rates range from
  **99.2824% to 99.9129%**. There are 650,108 VCF records with a GT FORMAT field;
  the remaining 3,709 records omit GT (intensity-only probes). Each sample has
  fully called genotypes at over 98% of the records with GT.
- Conversion reported 654,027 input loci, 0 missing-reference loci, and 210 skipped
  loci. Normalization realigned 1,337 records and skipped 0 for reference mismatch.
- Reusing `TEST_INITIAL` was rejected as expected, all three existing output file
  SHA-256 checksums remained unchanged, and the acquired lock was released.
- A second real conversion under `TEST_REPEAT` succeeded. All VCF records,
  including every FORMAT/sample field, have an identical SHA-256 digest after
  ordering sample columns consistently. Sample IDs, record counts, call rates,
  indexed regional query results, and cleanup also match.
- Input SHA-256 checksums remained unchanged after all three named runs. A local
  report is saved in `data/integration-validation.json`. Inputs, outputs, reports,
  and logs are excluded from Git.
- Filename changes are **pseudonymization**, not complete anonymization: embedded
  barcode/array-position fields remain in IDATs, and `.extra.tsv` retains barcode
  metadata. Sample-name/description/plate/well IDAT fields were empty. The VCF
  headers contain no input barcode. No source barcode values are recorded here.

These checks verify technical conversion, expected filename-derived sample IDs,
and repeatability. No independent truth genotypes were supplied for concordance
or biological identity verification.

## logshuru integration validation (2026-10-26)

- Bundled the unmodified first-party logshuru v2.0.0 release script and MIT license.
  Script SHA-256 matches
  `520cd796f8c2ad4a2a4a8298566731ba17c5e10a7e3392fdfa854f6bd5c2db6e`;
  the license checksum is recorded alongside it in `lib/logshuru/SHA256SUMS`.
  Both checks passed locally and during the image build.
- The pipeline sources the checkout library or the installed image copy. It uses
  direct severity-level calls and retains whole-run tool output capture. The
  duplicate logger file sink is disabled; timestamps default to UTC and colors
  default to off.
- Ten local tests passed, including command failure at every conversion stage,
  log filtering, JSON context, and a forced date/logger failure after a tool exits
  42. That original status survived; the lock was released and intermediates were
  retained despite the logger failing during both error and cleanup reporting.
- Rebuilt the image successfully, verified help, and converted all three real
  sample pairs under `TEST_LOGGING` with `LOG_LEVEL=DEBUG`.
- The complete VCF was decoded and checked for column count, sorting, and sample
  IDs. All 653,817 records, including every FORMAT/sample field, have the same
  digest as the pre-logger run after consistent sample-column ordering. CSI count
  matches, and the indexed regional query still returns 217 records.
- The combined log contains DEBUG, PROCESS, INFO, and SUCCESS events with actual
  application source/line context, plus raw idat2gtc/gtc2vcf and normalization
  diagnostics. No ANSI escapes or duplicate completion event were present.
- A real same-prefix rerun returned 1 with an ERROR event, left output checksums
  unchanged, and released its lock. Successful-run intermediates were removed.
- Local outputs are `data/TEST_LOGGING.{vcf.gz,vcf.gz.csi,extra.tsv}`; the private
  report is `data/logshuru-validation.json`. Results and logs remain Git-ignored.

### First-party library layout and test names

- idat2vcf and logshuru are both authored by Mohammed Mubeen Shaikh under
  `mubeenomics`. The logger is documented as a **bundled first-party library**
  in `lib/logshuru/`, with its separate version, MIT license, and checksum records.
  Third-party notices describe the external gtc2vcf plugins; first-party library
  attribution is in the README and `lib/logshuru/README.md`.
- After moving the library, all ten tests, Bash syntax checks, ShellCheck, local
  checksum verification, Docker build/checksums, and container help passed again.
- Generated fresh runs under `TEST_INITIAL`, `TEST_REPEAT`, and `TEST_LOGGING`
  using the rebuilt image. The first two use the default PROCESS log threshold;
  TEST_LOGGING uses DEBUG. Their logs record the actual requested project codes.
- All three runs produced 653,817 sorted/indexed records for the same three sample
  IDs. Complete canonical record digests match each other and the earlier baseline;
  indexed regional queries, call rates, log context, and cleanup checks passed.
- Reusing TEST_INITIAL returned 1 with an ERROR event and preserved output file
  checksums. All six input checksums remained unchanged across the three runs.
- Regenerated the active private reports with the requested test names. Earlier
  raw outputs, logs, and reports are retained in ignored `data/previous-runs/`.

## Quiet/verbose and external-project invocation (2026-10-26)

- Kept entrypoint-based invocation, with `[--verbose] PROJECT_CODE` arguments.
  No legacy-command dispatcher is needed. Documentation uses `project_code` and
  makes the single project-directory mount to `/data` the primary workflow.
- Default execution captures application events and raw tool stdout/stderr
  directly in the persistent log. Its console output is one final SUCCESS line
  on stdout, or one final FAILED line on stderr with nonzero status. `--verbose`
  additionally streams through tee. The final status follows intermediate cleanup,
  lock release, and draining/waiting for verbose capture.
- Logger initialization failures also produce a failure summary and diagnostic log.
  Help and argument validation do not create logs. Log-directory creation failures
  are reported directly. `LOG_LEVEL` filters events independently of console mode.
- Sixteen unit tests passed with Bash syntax and ShellCheck in the earlier
  invocation round; seventeen pass after console cleanup. Injected tool errors
  retained exit 42 despite logger, tee, or lock-cleanup failures. Successful tool
  execution followed by tee/cleanup failure returned nonzero without a successful
  final console summary. Verbose output was drained before the final summary.
- Rebuilt the current image and tested outside the repository at
  `/tmp/opencode/idat2vcf-invocation-qz8rxn0p`. Each test project contains its own
  `idat_files/`; only that whole project is mounted to `/data`, with a separate
  persistent log mount. No runtime code-repository mount is used.
- `TEST_INITIAL`: foreground quiet mode printed exactly one success line and no
  stderr. Its persistent log contains all configured severities and tool output.
- `TEST_REPEAT`: detached quiet mode returned a container ID immediately. Attached
  `docker logs -f` received only the final success summary, while a registered
  `docker wait` returned exit status 0. The full mounted log remains available
  after automatic container removal.
- `TEST_LOGGING`: foreground --verbose mode streamed actual idat2gtc/gtc2vcf
  diagnostics and application events, with its success summary last.
- Every run has the three expected sample IDs and 653,817 sorted/indexed records.
  Complete decoded canonical record digests match the prior baseline. Indexed
  regional queries returned 217 records and metadata call rates match the baseline.
  Logs contain exactly one post-cleanup completion event without ANSI escapes.
- Quiet and verbose same-prefix attempts returned 1, preserved output checksums,
  and released the lock. Both diagnostic logs include the overwrite-refusal reason;
  only verbose execution echoed those details to the console.
- Copied input checksums and original source input checksums remained unchanged.
  Run-owned intermediates and locks were removed after success. External projects
  and logs are retained at the test root above; the detailed private report is
  `data/invocation-validation.json` and records the tested image ID.

## Miniforge base upgrade (2026-10-26)

- Rebuilt the image with the current versioned base
  `condaforge/miniforge3:26.9.4-0` (built from `ubuntu:noble`, Ubuntu 24.04.5
  LTS at validation time), replacing `condaforge/miniforge3:25.3.1-0`. The
  resolved tag's amd64 manifest digest matches the digest currently referenced
  by upstream `latest`.
- Build-time checks passed: architecture test, bcftools=1.20 install, all seven
  resource checksums, plugin discovery, and both plugin help outputs. The mamba
  solver resolved bcftools 1.20 (build `h8b25389_1`, unchanged) with runtime
  htslib 1.24, plus newer system libraries. Recorded versions inside the image:
  `1.20+htslib-1.24`, conda 26.9.4, mamba 2.9.0.
- All 21 unit tests passed. Plugin loading and help output verified in the
  candidate container.
- Real-data quiet and verbose runs with the candidate image (per-project logs,
  explicit `HOST_LOG_DIR`) matched the established baseline: three sample IDs,
  653,817 sorted/indexed records, identical canonical digest, 217-record indexed
  regional query, baseline call rates, clean consoles, and full cleanup. A
  quiet overwrite attempt was refused with the host log path reported. Private
  report: `data/console-cleanup-validation.json` (test root
  `/tmp/opencode/idat2vcf-projectlogs-ckuca4w6`).
- A real `docker stop` during conversion exited 143 with the interruption
  warning, retained intermediates, released the lock, and logged the failure
  summary (test root `/tmp/opencode/idat2vcf-stop-ba8bw6lg`).
- Adopted the pinned base in `idat2vcf.Dockerfile`. Rebuilding `idat2vcf:local`
  from it reproduced the identical validated image ID
  (`sha256:4124fff72e24dc4921130244db8eb598c87371417a3dd1b8d20857ead465021b`,
  4,358,787,444 bytes, about 95 MB larger than the previous base). The
  temporary candidate tag was removed. Conversion behavior is baseline-identical;
  the benefit is a maintained toolchain (current Ubuntu base, conda/mamba, and
  sharded repodata support) rather than conversion-output changes.

## Console-output cleanup (2026-10-26)

- Removed genuine duplication and noise reported from a verbose run:
  - bcftools version information is captured with `--version-only` and logged as
    one compact event instead of streaming the full copyright/license banner.
  - The indexed record count from final validation is captured and logged at
    DEBUG instead of printing a bare number to the console or log.
  - The formatted completion event is appended only to the run log after all
    pipeline output drains; the console keeps exactly one final summary line.
- Legitimate repetitions remain: each plugin independently reads the BPM/EGT
  resources, and conversion/normalization each report their own `Lines` statistics.
- Seventeen unit tests pass with Bash syntax and ShellCheck, including new checks
  for banner suppression, captured index count, DEBUG-only details, file-only
  completion events, and no bare count on the console. The bcftools fixture now
  covers `--version-only` and emits idat2gtc-style progress so raw tool capture
  remains testable.
- Rebuilt `idat2vcf:local`
  `sha256:995d151232895aa4cbb03688d65d11be3fc60a3a994e8df5fda15036048afec5`
  (4,264,153,408 bytes). In this build, `bcftools --version-only` prints
  `1.20+htslib-1.22.1`, which is the single version event's content.
- Verified with real data outside the repository at
  `/tmp/opencode/idat2vcf-console-2rnzsto6`: `TEST_QUIET` (foreground quiet,
  PROCESS) printed exactly one success line with empty stderr. `TEST_VERBOSE`
  (foreground verbose, DEBUG) streamed diagnostics without the banner or bare
  count and ended with the summary line. Both runs produced 653,817 sorted/indexed
  records matching the baseline canonical digest, correct sample IDs, an indexed
  regional query of 217 records, baseline call rates, and full cleanup. Each log
  contains one compact version event and ends with the completion event; the
  DEBUG run's log includes `Indexed records: 653817`; `Reading BPM file` appears
  exactly twice per run (once per plugin). A quiet overwrite attempt returned 1,
  preserved output checksums, and logged the refusal reason.
- Final status summaries then changed to print the **host system log path** in
  both the SUCCESS and FAILED lines, instead of the bare filename or the container
  path. The host path is auto-detected from the bind-mount source recorded in
  `/proc/self/mountinfo` (verified to expose the real host directory under this
  rootless Docker setup), with an optional `-e HOST_LOG_DIR=…` override and a
  container-path fallback when detection is impossible. The startup log event
  shows the same host path.
- Rebuilt `idat2vcf:local`
  `sha256:572fd2712b76859379c36c9f3c0a7e60ddfade47f525e3ecd1019e5515e15af3`
  (4,264,153,997 bytes) and re-verified with real data outside the repository at
  `/tmp/opencode/idat2vcf-console-vhq5prlw`: quiet and verbose runs printed
  summaries ending with the auto-detected host log path, matching the actual host
  file locations, and a quiet overwrite attempt's FAILED line included it as well.
  Both runs produced 653,817 sorted/indexed records matching the baseline
  canonical digest, correct sample IDs, an indexed regional query of 217 records,
  baseline call rates, and full cleanup. Eighteen unit tests pass, including a
  HOST_LOG_DIR override check (with trailing-slash normalization) and a fallback
  check. Details are in `data/console-cleanup-validation.json`, which records
  the tested image ID. External projects and logs remain at the test roots above.
- These tests used a local filesystem outside the repository. An actual NAS mount
  was not supplied for a NAS-specific integration run.

## Docker setup history

### Docker build attempt (2026-10-26)

- Verified that Docker Engine 28.3.3 is reachable at
  `unix:///run/user/5252/docker.sock`, matching the current user's UID 5252.
  The existing `DOCKER_HOST` and saved contexts pointed to UID 1002 instead.
  Commands used an explicit `--host`; global configuration was not changed.
- Attempted:

  ```bash
  docker --host unix:///run/user/5252/docker.sock build \
    --platform linux/amd64 -f idat2vcf.Dockerfile -t idat2vcf:local .
  ```

- Docker fell back to its legacy builder because the Buildx CLI plugin was
  missing (`docker buildx` is not available). The Dockerfile requires BuildKit
  for its build-time resource mount and COPY permissions.
- Before reaching the installation/resource steps, the builder failed while
  preparing an `overlay2` container layer, with
  `merged/dev/console: value too large for defined data type`.
- A separate minimal check also failed:

  ```bash
  docker --host unix:///run/user/5252/docker.sock run --rm \
    condaforge/miniforge3:25.3.1-0 /bin/true
  ```

  Docker reported `merged/dev/shm: value too large for defined data type`.
  This uses the unchanged base image, so the failure is independent of the
  repository's conversion script and resource preparation.
- This initial build did not complete. The repair and successful retry are
  documented below.

### Rootless Docker repair and successful retry (2026-10-26)

- The daemon maps container root to host UID/GID 5252 and subordinate IDs to
  231072–296607. Existing image layers still had former host primary GID 1002,
  which is outside that namespace's mapping.
- Stopped the idle user Docker service and changed only former-GID-1002 entries
  owned by host UID 5252 under the Docker data directory to GID 5252, preserving
  UIDs, file contents, and permission modes. A manifest of 226,409 eligible
  directory entries (including hard links), plus one separately handled entry,
  is saved at `/tmp/opencode/docker-gid-repair-manifest.json`.
- One apt directory was owned by mapped container UID 42 rather than the host
  user. Corrected its group as that mapped owner through a directory descriptor,
  preserving its UID and mode. Other subordinate ownership mappings were retained.
- Restarted Docker and confirmed the unchanged Miniforge base image runs
  `/bin/true` successfully. No existing images or containers were deleted.
- Installed the official Linux amd64 Buildx 0.25.0 binary in
  `~/.docker/cli-plugins/docker-buildx`, after verifying upstream SHA-256
  `4104d79a791a8744c0b43fd5bd0a6172dff29040c5229946a1cdb2d27b0b5bfa`.
- Updated the `rootless` Docker context to the UID 5252 socket and changed the
  `.bashrc` DOCKER_HOST setting to use `$(id -u)` rather than hard-coded UID 1002.
  Existing processes can still inherit the old environment variable; refresh it
  with `export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"`, or unset it
  to use the corrected saved context. Verified the context works with DOCKER_HOST
  unset. No Git configuration was changed.
- Repeated the documented build successfully, followed by the checks above.

## Review and publication

- Local repository initialized with branch `main`.
- Project license selected: **MIT** (`LICENSE`), copyright Mohammed Mubeen Shaikh.
- GitHub visibility selected: public, for a later publication step.
- GitHub Actions workflow `.github/workflows/checks.yml` runs the Bash syntax
  check, ShellCheck, bundled logshuru checksum verification, and the unit tests
  on push/pull request. Resource-dependent Docker build and real-data conversion
  remain documented local integration checks.
- Initial local commit prepared with the tracked file set below; no GitHub
  repository or remote has been created yet.

### Files tracked in the initial commit

- Pipeline and image: `idat2vcf.docker.sh`, `idat2vcf.Dockerfile`
- Bundled library: `lib/logshuru/{logshuru.sh,LICENSE,SHA256SUMS,README.md}`
- Resources: `resources.sha256`, `THIRD_PARTY_NOTICES.md`
- Documentation: `README.md`, `PLAN.md`, `VALIDATION.md`, `docs/resources.md`
- Tests: `tests/test_pipeline.py`, `tests/fixtures/bcftools`
- Automation: `.github/workflows/checks.yml`, `.gitignore`, `.dockerignore`,
  `.gitattributes`, `LICENSE`

Excluded by design: the resource archive (`idat2vcf.grch38.tar.gz`), IDAT
inputs, generated outputs/logs, and local reports (`data/`, `idat_files/`,
`container_logs/`, and the archive itself).
