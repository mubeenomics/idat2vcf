# IDAT to VCF

Docker-based conversion of Illumina Infinium Global Screening Array v3.0 IDAT
intensity files into a jointly generated, sorted, normalized, compressed, and
indexed GRCh38 VCF using the `idat2gtc` and `gtc2vcf` bcftools plugins.

idat2vcf and its logging library
[logshuru](https://github.com/mubeenomics/logshuru) are first-party projects by
Mohammed Mubeen Shaikh under [mubeenomics](https://github.com/mubeenomics).

## Features

- One command per project: quiet final status by default, `--verbose` for live
  logs, `-d` for detached runs with `docker logs` monitoring.
- Persistent **per-project logs** in `logs/idat2vcf/` combining severity-based
  events with the complete raw bcftools diagnostics (bundled logshuru v2.0.0).
- Resources verified against checksums at image build time; bcftools 1.20 with
  pinned gtc2vcf 1.20-20240927 plugins.
- Run isolation with per-project locks, output protection, staged publication,
  and prompt Ctrl+C/`docker stop` handling.
- Rootless-Docker friendly: outputs land on the host as the calling user.

## Requirements

- Docker with BuildKit on `linux/amd64`.
- The local resource bundle `idat2vcf.grch38.tar.gz` next to the Dockerfile —
  see [docs/resources.md](docs/resources.md) for acquisition, exact versions,
  and checksums. Not included in Git.
- Space for the archive, approximately 3.8 GB of unpacked resources, the image,
  and conversion intermediates.

## Build

```bash
docker build --platform linux/amd64 -f idat2vcf.Dockerfile -t idat2vcf:local .
docker run --rm idat2vcf:local --help
```

The build installs bcftools 1.20 with the pinned plugins, verifies every
resource checksum, and checks that both plugins load. The archive is
build-mounted and is not retained in the image.

> **Note:** the built image embeds the Illumina manifests, cluster file, and the
> reference genome. Keep the image private; do not push it to a public registry.

## Quick start

From the project directory containing `idat_files/` (anywhere on the Docker
host, including a mounted NAS):

```text
project_folder/
├── idat_files/
│   ├── BARCODE_R01C01_Grn.idat
│   └── BARCODE_R01C01_Red.idat
└── logs/idat2vcf/
```

```bash
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

The foreground command waits, writes all pipeline events and tool output to the
per-project log, and prints one final status line:

```text
SUCCESS: PROJECT_001 completed. Log: /home/you/project_001/logs/idat2vcf/PROJECT_001_<timestamp>_<suffix>.log
```

Failures print `FAILED`, the project code, exit status, and the log path, and
return a nonzero exit code. Add `--verbose` after the image name to stream the
run live; use `-d` for detached execution with `docker logs -f` monitoring
(see [docs/usage.md](docs/usage.md)).

Each sample requires uncompressed `*_Grn.idat` and `*_Red.idat` files. Use a new
project code (letter/digit start; letters, digits, dot, underscore, hyphen) per
output set; existing outputs are never replaced.

### Outputs

All paths are relative to the project directory.

| File | Description |
|---|---|
| `PROJECT_CODE.vcf.gz` | Sorted, normalized, compressed VCF |
| `PROJECT_CODE.vcf.gz.csi` | CSI index |
| `PROJECT_CODE.extra.tsv` | Per-sample GTC metadata |
| `logs/idat2vcf/PROJECT_CODE_*.log` | Complete run log |

## Documentation

| Document | Contents |
|---|---|
| [docs/usage.md](docs/usage.md) | Invocation modes, stopping a run, mounts and permissions, outputs, conversion behavior |
| [docs/configuration.md](docs/configuration.md) | Environment variables and the logging reference |
| [docs/resources.md](docs/resources.md) | Reference/manifest/plugin provenance and bundle preparation |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Common failures and remedies |
| [docs/development.md](docs/development.md) | Development checks, tests, CI, and validation status |

## License

Released under the [MIT License](LICENSE), copyright Mohammed Mubeen Shaikh.
The bundled logshuru library keeps its own MIT license in
[lib/logshuru/LICENSE](lib/logshuru/LICENSE); third-party gtc2vcf plugin notices
are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The reference genome
and array resources remain subject to their providers' terms and are not
distributed by this repository.
