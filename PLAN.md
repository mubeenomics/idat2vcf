# Repository implementation plan

## Goal

Prepare a reproducible Docker-based IDAT → GTC → VCF pipeline, establish a clean
local Git repository, and publish to GitHub after local review and approval.
Retain bcftools 1.20 and gtc2vcf 1.20-20240927 initially.

## 1. Verify resources

- Inspect CSV genome-build metadata and confirm GRCh38 coordinates.
- Check BPM, CSV, and EGT compatibility and the FASTA index.
- Record filenames, URLs, versions, and SHA-256 checksums.
- Document Linux x86_64 plugin support.

## 2. Update container and script

- Extract resources and install plugins at image build time; configure
  BCFTOOLS_PLUGINS and check plugin loading.
- Retain pinned dependencies, clean caches, and configure a script entrypoint.
- Create logging directories before use; validate arguments and exact resources.
- Use unique run-owned intermediates, preserve them after failure, and clean only
  those intermediates after success.
- Prevent accidental output replacement and concurrent runs for the same prefix.
- Capture diagnostics from all stages and report failures and interruptions.
- Bundle first-party logshuru v2.0.0 with license/provenance, use event levels while
  retaining complete tool diagnostics, and preserve failure/cleanup exit behavior.
- Preserve conversion settings and document reference mismatch exclusion.
- Keep entrypoint-based invocation with a single project-directory mount to /data.
- Default to a persistent full log and final console status; --verbose adds live
  log streaming. Print status after cleanup and preserve tool/capture failures.
- Use project_code in invocation examples; support folders outside the repository
  and explain local/NAS permissions, foreground status, and detached monitoring.

## 3. Prepare repository files

- Add README.md with build/run commands, mounts, outputs, and troubleshooting.
- Add docs/resources.md with provenance, checksums, and bundle preparation.
- Add .gitignore, .dockerignore, and .gitattributes.
- Keep resource archives and genomic data outside Git history.
- Add a project license only after the owner chooses one; document upstream MIT
  attribution separately.

## 4. Initialize and validate locally

- Initialize Git with a main branch and inspect ignore rules and tracked scope.
- Run Bash syntax checks, ShellCheck if available, Docker build and plugin checks
  if Docker is available, and focused failure-path checks.
- Run an end-to-end conversion when representative IDAT inputs are available;
  verify VCF readability, index, expected samples, and repeat execution.
- Present changes and validation results for review.
- Create the initial commit after approval; do not change Git identity settings.

## 5. Publish after approval

- Confirm GitHub owner, repository name, visibility, and project license.
- Review intended files and commit history for data and large binaries.
- Create the GitHub repository with gh, add the remote, and push main.
- Add description, topics, and lightweight shell-check CI.
- Verify the published repository and return its URL.

## Pending decisions / inputs

- Resolved: project license is MIT (`LICENSE`); GitHub visibility will be public.
- GitHub publication itself is deferred; create the local commit first.

## Execution status

- Local Git repository initialized on `main`.
- Script, Dockerfile, resource checksums, documentation, exclusions, and focused
  orchestration tests implemented.
- Local resource inspection, syntax checks, ShellCheck, and twenty-one test cases
  passed, including log filtering, JSON events, logger failure during error
  handling, routing modes, host-path overrides, and prompt termination.
- Docker build initially failed due to old-GID ownership in rootless storage and
  missing Buildx. These issues were repaired while preserving existing images
  and containers, and the image now builds successfully.
- Real plugin loading, manifest-only conversion/sorting/normalization/indexing,
  and rootless mounted-directory logging/failure handling have passed. README
  run instructions were corrected for rootless versus rootful user mappings.
- Full real IDAT conversion and repeat-run validation passed with the three supplied
  filename-pseudonymized sample pairs. See `VALIDATION.md` for results and scope.
- logshuru v2.0.0 is bundled in `lib/logshuru/` with direct severity-level event calls.
  Full-run diagnostics remain captured, without a second logger file sink.
- The logger-enabled image was rebuilt and tested with all three real sample pairs
  under `TEST_LOGGING`. Record digests match the original result; severity/source
  context, raw tool capture, output protection, index, and cleanup checks passed.
- Fresh `TEST_INITIAL`, `TEST_REPEAT`, and `TEST_LOGGING` runs and reports now use
  the requested names. Prior raw artifacts are retained in ignored
  `data/previous-runs/`. Both projects are attributed to their author under
  mubeenomics, with first-party logshuru documentation in `lib/logshuru/`.
- Quiet/default and --verbose execution are implemented. Tests cover final summary
  ordering, quiet/verbose success and failure, initialization errors, and capture
  or cleanup failure without masking the original tool status.
- Console noise was removed after review: compact bcftools version event instead
  of the full banner, captured DEBUG index count instead of a bare number, and a
  file-only completion event for every logger routing mode so the console keeps
  one final summary. Status lines show the host system log path, passed
  explicitly as HOST_LOG_DIR in the documented commands (auto-detection remains
  a best-effort fallback; non-absolute overrides are rejected).
- Logs are documented per project in `<project>/logs/idat2vcf/`. INT/TERM now
  terminate the conversion pipeline promptly (background subshell, recursive
  child kill) while preserving cleanup. Twenty-one tests pass; real-data
  quiet/verbose reruns match prior record digests, and a real docker stop exited
  143 with the lock released and intermediates retained.
- Rebuilt and verified real-data foreground quiet, detached quiet, and foreground
  verbose runs from project directories outside the code repository using a single
  project mount. All results match the prior records; persistent logs, Docker
  monitoring, status summaries, output protection, and cleanup checks passed.
  See `data/invocation-validation.json` locally and `VALIDATION.md` for scope.
- Initial commit and GitHub publication await local review and approval.

### Commit preparation (2026-10-26)

- License chosen: MIT (`LICENSE`). Visibility chosen: public (for later).
- GitHub Actions workflow `.github/workflows/checks.yml` added for Bash syntax,
  ShellCheck, logshuru checksums, and unit tests; Docker build and real-data
  conversion remain documented local integration checks.
- README license/CI sections, VALIDATION.md review status, and this plan were
  updated accordingly.
- The initial local commit is created next; GitHub publication stays deferred.
