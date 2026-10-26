# Development checks

Testing, CI, and validation status.

[Usage](usage.md) · [Quick start](../README.md)

## Local checks

```bash
bash -n idat2vcf.docker.sh
shellcheck -x idat2vcf.docker.sh tests/fixtures/bcftools lib/logshuru/logshuru.sh
cd lib/logshuru && sha256sum -c SHA256SUMS && cd -
python3 -m unittest discover -s tests -v
```

The standard-library tests use a fake bcftools to test orchestration, pipeline
failure propagation, output protection, logging, and cleanup. They do not
validate biological results. A Docker build and representative IDAT conversion
are separate integration checks.

## Continuous integration

The same checks run automatically through GitHub Actions
(`.github/workflows/checks.yml`) on every push and pull request. The resource
archive and representative IDAT inputs are not available in CI, so the Docker
build and real-data conversion remain local integration checks.

## Status

See [VALIDATION.md](../VALIDATION.md) for the current validation status.
