# Validation status

Validated locally on 2026-10-26 and revalidated the same day after the
hardening changes recorded here.

[Development checks](docs/development.md) · [Quick start](README.md)

## Validated image

- `idat2vcf:local` `sha256:39206c05835e2bf61b9a5cb65f7e84bfbd6195e5b37842997d59dacea55e6fa0`
  (4,358,790,728 bytes, image labels `1.0.2`), built from the pinned base
  `condaforge/miniforge3:26.9.4-0` (Ubuntu 24.04.5 LTS), with bcftools **1.20**
  (package build `h8b25389_1`), runtime htslib **1.24** (pinned alongside
  bcftools so the tested pairing cannot silently drift), and the pinned
  gtc2vcf **1.20-20240927** plugins.

Rebuilding this Dockerfile at validation time reproduced the previously
validated image ID exactly, because the same resolved package set was cached.
This is not a general reproducibility guarantee: the transitive conda
dependency set is not locked, so future rebuilds are not guaranteed to be
bit-identical (see [docs/resources.md](docs/resources.md)).

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

- Bash syntax checks and ShellCheck for the pipeline, the test fixture, the
  smoke-test script, and the bundled first-party logger (sourced-library
  analysis enabled).
- **29** standard-library unit tests: conversion-stage failures, failed-run
  intermediate preservation, cleanup, project locks, output protection,
  quiet/verbose console modes, logger routing and failure semantics, prompt
  termination, Grn/Red pairing preflight (including a nested-directory layout,
  which the upstream plugin does not support), record-count deviation
  warnings/strict mode/invalid override handling, run log readability, and
  argument/help validation.
- A real-bcftools smoke test (`tests/smoke_bcftools.sh`) exercises the actual
  `sort | norm -c x | --write-index` stage on a tiny reference and VCF. It is a
  flag-level check only: in CI it runs with the runner's distribution bcftools
  (1.19 at the time of writing), not the pinned 1.20 build. The bundled plugins
  and the pinned build are covered by the local integration validation.
- The bundled logshuru release script and license match the recorded v2.0.0
  checksums; verified locally and at image build time.
- [CI](.github/workflows/checks.yml) runs all of these on every push and pull
  request, with a read-only `permissions` block and a SHA-pinned checkout.

## Docker integration checks

- Image build verifies resource checksums and plugin discovery/help; the
  resource archive is build-mounted and absent from the final image.
- Container help/entrypoint, plugin listing, and plugin help outputs verified.
- A manifest-only conversion loaded the BPM, CSV, EGT, and FASTA together:
  gtc2vcf reported 654,027 input loci, 0 missing-reference, 210 skipped;
  normalization produced 653,817 records, realigning 1,337 and excluding 0 for
  reference mismatch.

## Real-data integration

Three filename-pseudonymized GSA v3.0 sample pairs (uncompressed Red/Grn IDATs)
were converted with the actual container pipeline:

- Both conversion stages completed; three GTCs, then the VCF, CSI index, and
  per-sample metadata were produced. Successful runs cleaned up intermediates
  and locks.
- The VCF contains exactly the three expected sample IDs and **653,817**
  coordinate-sorted records; the full decoded stream matches the CSI count, and
  an index-backed query of `chr1:1000000-2000000` returned 217 records. The
  record count matches the bundle's validated value, so the deviation guard
  stays silent.
- Input preflight confirms the Grn/Red pairing (three paired samples, six
  files) and run logs are written group/other-readable.
- GTC call rates ranged from **99.28% to 99.91%**. There are 650,108 records
  with a GT FORMAT field (the remainder omit GT for intensity-only probes);
  each sample has fully called genotypes at over 98% of GT records.
- Conversion reported 654,027 input loci, 0 missing-reference, and 210 skipped;
  normalization realigned 1,337 records and excluded 0 for reference mismatch.
- **Repeatability:** a repeat conversion under a new project code produced
  records with an identical digest after consistent sample-column ordering. A
  same-prefix rerun was refused with existing output checksums unchanged and
  the lock released.
- **Deviation visibility:** an induced record-count deviation is reported both
  in the log and as a console `NOTE` in quiet mode; with
  `EXPECTED_VCF_RECORDS_STRICT` set it fails the run before publication with
  the dedicated exit status 65. A non-numeric `EXPECTED_VCF_RECORDS` is
  rejected at startup before any files are created.
- **Interruption:** `docker stop` during conversion exited 143, killed the tool
  processes, retained intermediates, released the lock, and logged the
  interruption.
- **Console modes:** quiet runs print one final status line; verbose runs
  stream diagnostics without the version banner; logs are written per project
  to `logs/idat2vcf/` with host-path status lines; input checksums remained
  unchanged throughout.

## Scope and caveats

- These checks verify technical conversion, filename-derived sample IDs, and
  repeatability. No independent truth genotypes were supplied for concordance
  or biological identity verification.
- Filename changes are **pseudonymization, not anonymization**: embedded
  barcode/array-position metadata remains in IDATs, and `.extra.tsv` can retain
  those identifiers. VCF headers contain no input barcode.
- Only the documented GRCh38 bundle is validated; GRCh37 support is not
  implemented.
- NAS-backed mounts were not integration-tested; the documented
  `HOST_LOG_DIR` setting is the reliable path display for any mount layout.
