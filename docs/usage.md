# Usage guide

Running, stopping, mounts, permissions, outputs, and conversion behavior.

[Quick start](../README.md) · [Configuration](configuration.md) · [Resources](resources.md)

## Inputs and project layout

Go to the project directory containing `idat_files/`. It can be anywhere on the
Docker host, including a mounted NAS; it does not need to be in this repository.
Each sample requires uncompressed `*_Grn.idat` and `*_Red.idat` files for GSA
v3.0. Logs are stored **per project** in `<project_directory>/logs/idat2vcf/`;
create it before running.

```text
project_folder/
├── idat_files/
│   ├── BARCODE_R01C01_Grn.idat
│   └── BARCODE_R01C01_Red.idat
└── logs/idat2vcf/
```

## Invocation modes

The image entrypoint selects the conversion script; arguments after the image
name are pipeline arguments. `--help` describes all of them.

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

The foreground command waits, saves all pipeline events/tool output in a
persistent log, and prints one final status line:

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

### Show live logs with --verbose

```bash
docker run --rm --init --platform linux/amd64 \
  -e HOST_LOG_DIR="$log_directory" \
  -v "$log_directory:/container_logs" \
  -v "$PWD:/data" \
  idat2vcf:local --verbose "$project_code"
```

`--verbose` streams the same events and raw tool diagnostics saved to the log,
followed by the final summary. It may also appear after the project code.

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

## Project codes

Project codes must start with a letter/digit and contain only letters, digits,
dot, underscore, or hyphen. If the directory name is unsuitable, set an explicit
value such as `project_code=PROJECT_001` instead of deriving it from the
directory. Use a new project code for each output set; existing outputs are
never replaced (see [outputs](#outputs)).

## Stopping a run

Ctrl+C (foreground) and `docker stop` terminate the conversion promptly. The
pipeline kills its tool processes, retains the run's intermediate directory,
releases the project lock, reports exit status 143, and records the interruption
in the log. Remove a retained hidden `.PROJECT_CODE.idat2vcf.*` working directory
manually once no run is active.

## Mounts, permissions, and storage

Two mounts supply the project data and its log directory:
`-v "$PWD:/data"` reads `$PWD/idat_files/` and writes results directly into
`$PWD`; `-v "$log_directory:/container_logs"` stores run logs under
`$PWD/logs/idat2vcf/`. Both filesystems must be accessible to Docker and
writable by the mapped user. This applies to local disks and mounted NAS storage
alike. Intermediates and sorting files use the project filesystem, so its
storage performance affects runs. A centralized alternative such as
`-v "$HOME/container_logs:/container_logs"` (with matching `HOST_LOG_DIR`) also
works if you prefer logs outside the projects.

This command is suitable for **rootless Docker**, where the default container
root user maps to your host account and produces host-owned outputs. Do not add
your host numeric UID with `--user` under rootless Docker: that selects a
different mapped user and can prevent writes to the mounted directories.

For **rootful Docker**, add `--user "$(id -u):$(id -g)"` to keep host outputs
owned by your account. Both output and log directories must be writable by the
mapped user. The optional `--init` adds signal forwarding to its child and reaps
orphaned processes; it does not control logging or start conversion. For an
interactive shell, use `docker run --rm -it --entrypoint bash idat2vcf:local`.

If input storage is separate from the project/output directory, an optional
extra mount such as `-v "/absolute/input/path:/data/idat_files:ro"` exposes
those inputs read-only. This nested mount may create an empty `idat_files/`
mount-point directory in the output directory. It is not needed for the standard
single-project layout.

## Outputs

- `$PWD/PROJECT_CODE.vcf.gz`
- `$PWD/PROJECT_CODE.vcf.gz.csi`
- `$PWD/PROJECT_CODE.extra.tsv` — per-sample GTC metadata
- `$PWD/logs/idat2vcf/PROJECT_CODE_<UTC timestamp>_<unique suffix>.log`

Renaming IDATs with sample aliases changes the filename-derived VCF sample IDs,
but does not remove embedded barcode/array-position metadata from the binary
inputs. The `.extra.tsv` output can retain those identifiers and scanner
metadata. Inputs and generated outputs/logs are excluded from Git.

The script refuses to replace any existing output. It uses a per-project lock,
a unique working directory under `/data`, and only the GTCs from that run.
Successful runs remove their working directory. Failed runs preserve it and log
its location. Existing `/data/gtc_files` directories are not used.

Outputs are staged and validated before publication. Publishing the three files
is not a single filesystem transaction; if interrupted during publication,
inspect and move aside any partial final output set before rerunning.

## Conversion behavior

The conversion follows the upstream pipeline:

1. Call genotypes from IDAT pairs with `bcftools +idat2gtc`.
2. Convert the run's GTC files jointly with `bcftools +gtc2vcf`.
3. Sort and normalize against the GRCh38 reference and write a CSI index.

`bcftools norm -c x` **excludes reference-mismatching records**. Review
conversion and normalization diagnostics in the log. Duplicates are not
automatically removed. Sample names follow the upstream default (GTC filenames).
No additional sample/variant QC filtering is applied. Genotype correctness and
sample identity should be checked with representative inputs before production
use.

The pipeline preflights the input pairing: every top-level `*_Grn.idat` must
have a same-directory `*_Red.idat` match, and the counts must agree, so mistakes
fail before genotyping starts. The search is top-level only because the upstream
plugin does not recurse into subdirectories. Files not following the `_Grn/_Red`
naming are warned about (in the log and as a console `NOTE`) and ignored. After
conversion, the indexed record count is compared with the validated count for
the pinned bundle (653,817); a deviation logs a `WARNING` and a console `NOTE`,
and with `EXPECTED_VCF_RECORDS_STRICT` set it fails the run before publication.
