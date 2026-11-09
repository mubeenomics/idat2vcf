# Validation status

Validated locally on 2026-11-09 with public sample data that anyone can
download and rerun.

[Development checks](docs/development.md) · [Quick start](README.md)

## Validated image

- `idat2vcf:1.0.3` `sha256:2e12a620457f01e4262117dd44c3ce970e7d4f41f273489cfbbcc09dcc0ecf05`
  (4,358,855,370 bytes, image labels `1.0.3`), built from the digest-pinned base
  `condaforge/miniforge3:26.9.4-0` (Ubuntu 24.04.5 LTS), with bcftools **1.20**
  (package build `h8b25389_1`), runtime htslib **1.24** (pinned alongside
  bcftools so the tested pairing cannot silently drift), and the pinned
  gtc2vcf **1.20-20240927** plugins.

The transitive conda dependency set is not locked, so future rebuilds are not
guaranteed to be bit-identical (see [docs/resources.md](docs/resources.md)).

## Resource verification

- SHA-256 inventory of all seven files in the supplied archive
  ([resources.sha256](resources.sha256)); except for the plugins, checksums
  fingerprint the supplied bundle rather than fresh provider downloads.
- Both plugin binaries match the official
  [`gtc2vcf_1.20-20240927.zip`](https://software.broadinstitute.org/software/gtc2vcf/gtc2vcf_1.20-20240927.zip)
  release exactly.
- All 195 FASTA index entries match sequence names, lengths, byte offsets, and
  line widths recomputed from the supplied FASTA.
- All 654,027 CSV assay records declare `GenomeBuild=38`; the CSV descriptor
  names the bundled BPM, and the BPM/EGT headers identify GSA v3.0.

## Automated checks

- Bash syntax checks and ShellCheck for the pipeline, the sample-data fetch
  script, the test fixture, the smoke-test script, and the bundled first-party
  logger (sourced-library analysis enabled).
- **34** standard-library unit tests: conversion-stage failures, failed-run
  intermediate preservation, cleanup, project locks, output protection,
  output-permission umask handling, quiet/verbose console modes, logger routing
  and failure semantics, prompt termination, Grn/Red pairing preflight
  (including a nested-directory layout, which the upstream plugin does not
  support), record-count deviation warnings/strict mode/invalid override
  handling, run log readability, and argument/help validation.
- A real-bcftools smoke test (`tests/smoke_bcftools.sh`) exercises the actual
  `sort | norm -c x | --write-index` stage on a tiny reference and VCF. In CI it
  runs with the runner's distribution bcftools, not the pinned 1.20 build;
  locally it also passed inside the validated image.
- The bundled logshuru release script and license match the recorded v2.0.0
  checksums; verified locally and at image build time.
- [CI](.github/workflows/checks.yml) runs all of these on every push and pull
  request, with a read-only `permissions` block and a SHA-pinned checkout.

## Docker integration checks

- Image build verifies resource checksums and plugin discovery/help; the
  resource archive is build-mounted and absent from the final image.
- Container help/entrypoint, plugin listing, and plugin help outputs verified.

## Public sample integration (GSE272121)

The public IDAT pair fetched by `scripts/fetch-sample-data.sh` (GEO
[GSM8393537](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSM8393537),
normal human astrocytes; see [docs/usage.md](docs/usage.md#public-sample-data))
was converted with the documented hardened command (`--network none --cap-drop
ALL --security-opt no-new-privileges`) on rootless Docker:

- The fetch script verified both pinned download checksums, and the run's
  input checksums remained unchanged throughout.
- Both conversion stages completed; the GTC, VCF, CSI index, and per-sample
  metadata were produced. Successful runs cleaned up intermediates and locks.
- GTC call rate **99.27%**. The VCF contains the one expected sample ID
  (`208358440099_R01C01`) and **653,817** coordinate-sorted records; the full
  decoded stream matches the CSI count, and an index-backed query of
  `chr1:1000000-2000000` returned 217 records. The record count matches the
  bundle's validated value, so the deviation guard stays silent.
- 650,108 records carry a GT FORMAT field (the remainder omit GT for
  intensity-only probes); 99.27% of them have a called genotype.
- Conversion reported 654,027 input loci, 0 missing-reference, and 210 skipped;
  normalization realigned 1,337 records and excluded 0 for reference mismatch.
- **Output permissions:** the VCF, index, `.extra.tsv`, and run log were
  written with mode `0640` under the default umask `027`.
- **Repeatability:** a detached `--verbose` run under a new project code
  produced records with an identical digest. A same-prefix rerun was refused
  with existing output checksums unchanged and the lock released.
- **Deviation visibility:** an induced record-count deviation is reported both
  in the log and as a console `NOTE` in quiet mode; with
  `EXPECTED_VCF_RECORDS_STRICT` set it fails the run before publication with
  the dedicated exit status 65. A non-numeric `EXPECTED_VCF_RECORDS` is
  rejected at startup before any files or logs are created.
- **Interruption:** `docker stop` during conversion exited 143, retained
  intermediates, released the lock, and logged the termination.
- **Console modes:** quiet runs print one final status line; verbose runs
  stream diagnostics without the version banner; logs are written per project
  to `logs/idat2vcf/` with host-path status lines.

## Scope and caveats

- These checks verify technical conversion, filename-derived sample IDs, and
  repeatability. No independent truth genotypes were available for concordance
  or biological identity verification.
- The public sample was run on a GSA v3.0-based BeadChip whose IDATs contain
  every GSA v3.0 bead address. It exercises a single-sample conversion; joint
  multi-sample conversion is covered by the orchestration tests, not by this
  dataset.
- Only the documented GRCh38 bundle is validated; GRCh37 support is not
  implemented.
- Rootful Docker and NAS-backed mounts were not integration-tested; the
  documented `HOST_LOG_DIR` setting is the reliable path display for any mount
  layout.
