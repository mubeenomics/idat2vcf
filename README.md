# IDAT to VCF

Docker-based conversion of Illumina Infinium Global Screening Array v3.0 IDAT
intensity files into a jointly generated, sorted, normalized, compressed, and
indexed GRCh38 VCF using the `idat2gtc` and `gtc2vcf` bcftools plugins.

idat2vcf and logshuru are first-party projects created by Mohammed Mubeen Shaikh
under [mubeenomics](https://github.com/mubeenomics). The expected project repository
is [mubeenomics/idat2vcf](https://github.com/mubeenomics/idat2vcf); its logging library
is maintained in [mubeenomics/logshuru](https://github.com/mubeenomics/logshuru).

## Supported configuration

- Linux x86_64 container (`linux/amd64`).
- bcftools **1.20**, with plugins from **1.20-20240927**.
- Bundled first-party **logshuru v2.0.0** for event logging (Bash 4.2+/GNU date).
- GSA v3.0 A2 BPM/CSV manifests and A1 cluster file listed in
  [resource documentation](docs/resources.md).
- `GCA_000001405.15_GRCh38_no_alt_analysis_set.fna` with its FASTA index.

The local resource bundle is intentionally excluded from Git. Obtain or assemble
`idat2vcf.grch38.tar.gz` as described in [docs/resources.md](docs/resources.md).
The build verifies all seven unpacked files against `resources.sha256`.

## Build

Requires Docker with BuildKit and network access to obtain the base image and
conda packages. Allow space for the archive, approximately 3.76 GB of unpacked
resources, the image, and conversion intermediates.

```bash
docker build --platform linux/amd64 -f idat2vcf.Dockerfile -t idat2vcf:local .
docker run --rm idat2vcf:local --help
```

Resources are prepared once at image build time. The build checks that both
plugins load and produce their help text. The resource archive is build-mounted
and is not retained in the image.

## Prepare inputs and run

Go to the project directory containing `idat_files/`. This can be anywhere on the
Docker host, including a mounted NAS; it does not need to be in this repository.
Each sample requires uncompressed `*_Grn.idat` and `*_Red.idat` files for this array.
Use a new project code for each output set.

```text
project_folder/
├── idat_files/
│   ├── BARCODE_R01C01_Grn.idat
│   └── BARCODE_R01C01_Red.idat
└── logs/idat2vcf/
```

Logs are stored **per project** in `<project_directory>/logs/idat2vcf/`, so they
stay beside the data they describe. Create it before running.

### Default: save the log and show the final status

```bash
# Run from the project directory containing idat_files/.
project_code=$(basename -- "$PWD")
project_code=${project_code^^}
log_directory="$PWD/logs/idat2vcf"
mkdir -p "$log_directory"

docker run --rm --init --platform linux/amd64 \
  -e HOST_LOG_DIR="$log_directory" \
  -v "$log_directory:/container_logs" \
  -v "$PWD:/data" \
  idat2vcf:local "$project_code"
```

The image entrypoint selects the conversion script; only the project code is
required after the image name. The foreground command waits, saves all pipeline
events/tool output in a persistent log, and prints one final status line:

```text
SUCCESS: PROJECT_001 completed. Log: /home/you/project_001/logs/idat2vcf/PROJECT_001_<timestamp>_<suffix>.log
```

Failure returns a nonzero exit code and prints `FAILED`, the project code, exit
status, and the full log path on stderr. The path shown is the **host system
path**. The documented commands pass it explicitly with
`-e HOST_LOG_DIR="$log_directory"`, which is reliable for every mount layout,
including NAS storage. Without it, the pipeline reads the bind-mount source from
`/proc/self/mountinfo` as a best-effort fallback and shows the container path
when the source cannot be resolved. The final status follows cleanup and log
draining and is independent of `LOG_LEVEL` severity filtering. Argument/help
errors and inability to create a log are reported directly before conversion
begins.

Project codes must start with a letter/digit and contain only letters, digits,
dot, underscore, or hyphen. If the directory name is unsuitable, set an explicit
value such as `project_code=PROJECT_001` instead of deriving it from the directory.

### Show live logs with --verbose

```bash
docker run --rm --init --platform linux/amd64 \
  -e HOST_LOG_DIR="$log_directory" \
  -v "$log_directory:/container_logs" \
  -v "$PWD:/data" \
  idat2vcf:local --verbose "$project_code"
```

`--verbose` is a pipeline argument **after the image name**. It streams the same
events and raw tool diagnostics saved to the log, followed by the final summary.
It may also appear after the project code. `--help` describes both modes.

### Detached execution

```bash
docker run -d --rm --init \
  --name "idat2vcf-${project_code}" \
  -e HOST_LOG_DIR="$log_directory" \
  -v "$log_directory:/container_logs" \
  -v "$PWD:/data" \
  idat2vcf:local --verbose "$project_code"

docker logs -f "idat2vcf-${project_code}"
```

With `-d`, Docker immediately returns a container ID rather than waiting to print
completion status. Use foreground execution for a direct completion/exit status
in the invoking shell. Detached runs can be quiet or verbose: `docker logs` shows
the selected console output (summary only in quiet mode). `--rm` removes the
completed container; the mounted log remains available afterward. This batch job
does not need `-i` or `-t`.

### Stopping a run

Ctrl+C (foreground) and `docker stop` terminate the conversion promptly. The
pipeline kills its tool processes, retains the run's intermediate directory,
releases the project lock, reports exit status 143, and records the interruption
in the log. Remove a retained hidden `.PROJECT_CODE.idat2vcf.*` working directory
manually once no run is active.

### Mounts, permissions, and storage

Two mounts supply the project data and its log directory:
`-v "$PWD:/data"` reads `$PWD/idat_files/` and writes results directly into
`$PWD`; `-v "$log_directory:/container_logs"` stores run logs under
`$PWD/logs/idat2vcf/`. Both filesystems must be accessible to Docker and writable
by the mapped user. This applies to local disks and mounted NAS storage alike.
Intermediates and sorting files use the project filesystem, so its storage
performance affects runs. A centralized alternative such as
`-v "$HOME/container_logs:/container_logs"` (with matching `HOST_LOG_DIR`) also
works if you prefer logs outside the projects.

This command is suitable for **rootless Docker**, where the default container
root user maps to your host account and produces host-owned outputs. Do not add
your host numeric UID with `--user` under rootless Docker: that selects a different
mapped user and can prevent writes to the mounted directories.

For **rootful Docker**, add `--user "$(id -u):$(id -g)"` to keep host outputs owned
by your account. Both output and log directories must be writable by the mapped
user. The optional `--init` adds signal forwarding to its child and reaps orphaned
processes; it does not control logging or start conversion. For an interactive shell, use
`docker run --rm -it --entrypoint bash idat2vcf:local`.

If input storage is separate from the project/output directory, an optional extra
mount such as `-v "/absolute/input/path:/data/idat_files:ro"` exposes those inputs
read-only. This nested mount may create an empty `idat_files/` mount-point directory
in the output directory. It is not needed for the standard single-project layout.

### Outputs

- `$PWD/PROJECT_CODE.vcf.gz`
- `$PWD/PROJECT_CODE.vcf.gz.csi`
- `$PWD/PROJECT_CODE.extra.tsv` — per-sample GTC metadata
- `$PWD/logs/idat2vcf/PROJECT_CODE_<UTC timestamp>_<unique suffix>.log`

Renaming IDATs with sample aliases changes the filename-derived VCF sample IDs,
but does not remove embedded barcode/array-position metadata from the binary
inputs. The `.extra.tsv` output can retain those identifiers and scanner metadata.
Inputs and generated outputs/logs are excluded from Git.

The script refuses to replace any existing output. It uses a per-project lock,
a unique working directory under `/data`, and only the GTCs from that run.
Successful runs remove their working directory. Failed runs preserve it and log
its location. Existing `/data/gtc_files` directories are not used.

Outputs are staged and validated before publication. Publishing the three files
is not a single filesystem transaction; if interrupted during publication,
inspect and move aside any partial final output set before rerunning.

### Conversion behavior

The conversion follows the upstream pipeline:

1. Call genotypes from IDAT pairs with `bcftools +idat2gtc`.
2. Convert the run's GTC files jointly with `bcftools +gtc2vcf`.
3. Sort and normalize against the GRCh38 reference and write a CSI index.

`bcftools norm -c x` **excludes reference-mismatching records**. Review conversion
and normalization diagnostics in the log. Duplicates are not automatically
removed. Sample names follow the upstream default (GTC filenames). No additional
sample/variant QC filtering is applied. Genotype correctness and sample identity
should be checked with representative inputs before production use.

### Paths

Defaults may be overridden using Docker `-e` options:

| Variable | Default | Purpose |
|---|---|---|
| `DATA_DIR` | `/data` | Contains `idat_files/`, outputs, and run intermediates |
| `LOG_DIR` | `/container_logs` | Persistent logs; created if missing |
| `IDAT2VCF_RESOURCES_DIR` | `/idat2vcf_resources` | Exact resource set used at build time |
| `HOST_LOG_DIR` | Best-effort auto-detection | Host directory of the log mount, shown in status lines; pass it explicitly for NAS or nested mounts |

### Logging

The pipeline sources a pinned, checksum-verified copy of
[logshuru v2.0.0](https://github.com/mubeenomics/logshuru/releases/tag/v2.0.0).
No runtime download is required. Pipeline events include a millisecond timestamp,
severity, source file, function, and line number, for example:

```text
2026-10-26 12:00:00.123 | PROCESS  | idat2vcf:main:327 - Starting IDAT to GTC conversion
```

Stage events use `PROCESS`, informational summaries use `INFO`, the working path
and indexed record count use `DEBUG`, post-cleanup completion uses `SUCCESS`,
interruptions use `WARNING`, and failures use `ERROR`. Direct event calls retain
their actual source location. bcftools version information is logged as one
compact event instead of printing the full copyright banner. The formatted
completion event is written only to the run log; the console receives a single
final summary line, avoiding duplicate completion messages.

Set Docker environment options to adjust the logger:

| Variable | Default | Purpose |
|---|---|---|
| `LOG_LEVEL` | `PROCESS` | Minimum event severity; use `DEBUG` for additional details |
| `LOGSHURU_TZ` | `UTC` | Event timestamp timezone |
| `LOGSHURU_TIMESTAMP_FORMAT` | `%F %T.%3N` | GNU date timestamp format |
| `LOGSHURU_COLOR` | `never` | Plain logs by default; upstream also accepts `auto`/`always` |
| `LOGSHURU_OUTPUT` | `stderr` | Logger stream before combined run capture |
| `LOGSHURU_FORMAT` | `text` | Event format, `text` or `json` |

For example, add `-e LOG_LEVEL=DEBUG` to the run command. Severity order is
`TRACE → DEBUG → PROCESS → INFO → SUCCESS → WARNING → ERROR → CRITICAL`.

The unique `.log` file retains **both application events and raw bcftools
diagnostics** in both modes. Quiet execution redirects directly to the file;
`--verbose` additionally streams through `tee`. Console visibility is independent
of `LOG_LEVEL`: that setting filters application events, not raw tool messages or
the final console status. `LOGSHURU_FILE` is intentionally disabled
by the pipeline to avoid duplicate copies of events; `LOG_DIR` selects the run-log
directory. JSON mode applies only to application events: the combined log still
contains plain tool output and is **not** a JSON Lines file.

ERROR events do not implicitly exit. The pipeline explicitly handles failure,
preserves command exit status, and releases its lock even when error/cleanup
logging itself fails. A normal unhandled logger failure also stops the run under
strict mode. Invalid logger configuration fails before the project lock is acquired
and produces a failure summary pointing to its diagnostic log. Verbose capture
failures return nonzero without masking an existing tool error.

## Troubleshooting

- **Cannot connect to Docker daemon:** start the appropriate Docker service before
  building or running.
- **Checksum failure:** use the exact resource versions documented below; do not
  silently rename alternative references/manifests to bypass the checks.
- **Plugin unavailable / loader error:** confirm an amd64 image and the pinned
  plugin/bcftools pairing. The newest upstream binaries target a different version.
- **Existing output:** choose a new project code or move the previous output set
  aside after reviewing it.
- **Project lock exists:** check that no run is active. A force-killed container
  can leave `$PWD/.PROJECT_CODE.idat2vcf.lock`; remove that empty directory only
  after confirming the run is no longer active.
- **Conversion failed:** inspect the log and preserved hidden working directory.
  These intermediates can be removed manually when no longer needed.

## Development checks

```bash
bash -n idat2vcf.docker.sh
shellcheck -x idat2vcf.docker.sh tests/fixtures/bcftools lib/logshuru/logshuru.sh
cd lib/logshuru && sha256sum -c SHA256SUMS && cd -
python3 -m unittest discover -s tests -v
```

The same checks run automatically through GitHub Actions
(`.github/workflows/checks.yml`) on every push and pull request. The resource
archive and representative IDAT inputs are not available in CI, so the Docker
build and real-data conversion remain local integration checks.

The standard-library tests use a fake bcftools to test orchestration, pipeline
failure propagation, output protection, logging, and cleanup. They do not validate
biological results. A Docker build and representative IDAT conversion are separate
integration checks. See [VALIDATION.md](VALIDATION.md) for the current status and
[PLAN.md](PLAN.md) for local review and later GitHub publication steps.

## Attribution and license

The plugins are developed by Giulio Genovese in
[freeseek/gtc2vcf](https://github.com/freeseek/gtc2vcf), with release downloads
hosted by the [Broad Institute](https://software.broadinstitute.org/software/gtc2vcf/).
They are MIT-licensed; see [docs/resources.md](docs/resources.md). NCBI supplies
the reference and Illumina supplies the array resources.

logshuru is a bundled first-party library, MIT-licensed, copyright Mohammed Mubeen
Shaikh. Its unmodified release script, license, checksums, and provenance are in
[lib/logshuru/](lib/logshuru/). The image includes these under
`/usr/local/share/idat2vcf/logshuru/`.
See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party plugin notices.

## License

This project is released under the [MIT License](LICENSE), copyright
Mohammed Mubeen Shaikh. The bundled logshuru library keeps its own MIT license in
[lib/logshuru/LICENSE](lib/logshuru/LICENSE), and the third-party gtc2vcf plugin
notices are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The reference
genome and array resources remain subject to their providers' terms and are not
distributed by this repository.
