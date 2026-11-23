# idat2vcf

[![CI](https://github.com/mubeenomics/idat2vcf/actions/workflows/ci.yml/badge.svg)](https://github.com/mubeenomics/idat2vcf/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/mubeenomics/idat2vcf)](https://github.com/mubeenomics/idat2vcf/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Docker-based conversion of Illumina Infinium Global Screening Array v3.0 IDAT
intensity files into a jointly generated, sorted, normalized, compressed, and
indexed GRCh38 VCF using the `idat2gtc` and `gtc2vcf` bcftools plugins.

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
- The local resource bundle `idat2vcf.grch38.tar.gz` next to the Dockerfile.
  See [docs/resources.md](docs/resources.md) for acquisition, exact versions,
  and checksums. Not included in Git.
- Space for the archive, approximately 3.7 GB of unpacked resources, the image,
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
  --network none --cap-drop ALL --security-opt no-new-privileges \
  -e HOST_LOG_DIR="$log_directory" \
  -v "$log_directory:/container_logs" \
  -v "$PWD:/data" \
  idat2vcf:local "$project_code"
```

The flags after `--init` are deliberate: the conversion needs no network, and
dropping capabilities and privilege escalation shrinks the container's access
while it handles human genotype data. On **rootful Docker**, `--user
"$(id -u):$(id -g)"` is **required** with these flags: without it the run
executes as root, and with all capabilities dropped root can no longer write
into a user-owned project directory. See [docs/usage.md](docs/usage.md) for
the full mount, user, and output-permission notes.

The foreground command waits, writes all pipeline events and tool output to the
per-project log, and prints one final status line:

```text
SUCCESS: PROJECT_001 completed. Log: /home/you/project_001/logs/idat2vcf/PROJECT_001_<timestamp>_<suffix>.log
```

Failures print `FAILED`, the project code, exit status, and the log path, and
return a nonzero exit code. Add `--verbose` after the image name to stream the
run live; use `-d` for detached execution with `docker logs -f` monitoring
(see [docs/usage.md](docs/usage.md)).

### Try it with public sample data

No IDATs of your own yet? `scripts/fetch_sample_data.sh` downloads one public
IDAT pair from NCBI GEO (GSE272121, about 10 MB) into a ready-made project
directory. Run the command above from that directory. See
[docs/usage.md](docs/usage.md#public-sample-data) for the source and expected
result.

```bash
scripts/fetch_sample_data.sh ~/idat2vcf-sample && cd ~/idat2vcf-sample
```

### Input requirements

Each sample requires uncompressed `*_Grn.idat` and `*_Red.idat` files. Use a new
project code (letter/digit start; letters, digits, dot, underscore, hyphen) per
output set; existing outputs are never replaced.

### Outputs

All paths are relative to the project directory.

| File | Description |
| --- | --- |
| `PROJECT_CODE.vcf.gz` | Sorted, normalized, compressed VCF |
| `PROJECT_CODE.vcf.gz.csi` | CSI index |
| `PROJECT_CODE.extra.tsv` | Per-sample GTC metadata |
| `logs/idat2vcf/PROJECT_CODE_*.log` | Complete run log |

## Documentation

- [Usage](docs/usage.md): invocation modes, stopping a run, mounts and permissions, outputs, conversion behavior.
- [Configuration](docs/configuration.md): environment variables and the logging reference.
- [Resources](docs/resources.md): reference/manifest/plugin provenance and bundle preparation.
- [Troubleshooting](docs/troubleshooting.md): common failures and remedies.
- [Contributing](CONTRIBUTING.md): development checks, tests, CI, and validation status.

## Support

Check [docs/troubleshooting.md](docs/troubleshooting.md) first. To report a bug
or ask a question, open an issue at
[github.com/mubeenomics/idat2vcf/issues](https://github.com/mubeenomics/idat2vcf/issues)
and include the relevant run log from `logs/idat2vcf/`.

> **Note:** never attach IDAT, GTC, or VCF files derived from real individuals to
> an issue. Reproduce the problem with the
> [public sample data](#try-it-with-public-sample-data) where possible.

## Contributing

Issues and pull requests are welcome. Before opening a pull request, run the
local checks in [CONTRIBUTING.md](CONTRIBUTING.md) (Bash syntax,
ShellCheck, checksums, unit tests, and the bcftools smoke test); CI runs the
same checks on every push and pull request.

## Acknowledgments

- [gtc2vcf](https://github.com/freeseek/gtc2vcf) (`idat2gtc` and `gtc2vcf`
  plugins) by Giulio Genovese. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- [bcftools and HTSlib](https://www.htslib.org/) for VCF processing.
- Illumina for the Infinium Global Screening Array v3.0 manifests and cluster file.
- [logshuru](https://github.com/mubeenomics/logshuru) for pipeline logging.

## License

Released under the [MIT License](LICENSE), copyright Mohammed Mubeen Shaikh.
The bundled logshuru library keeps its own MIT license in
[lib/logshuru/LICENSE](lib/logshuru/LICENSE); third-party gtc2vcf plugin notices
are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The reference genome
and array resources remain subject to their providers' terms and are not
distributed by this repository.
