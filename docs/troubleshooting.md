# Troubleshooting

[Usage](usage.md) · [Configuration](configuration.md) · [Quick start](../README.md)

- **Cannot connect to Docker daemon:** start the appropriate Docker service
  before building or running.
- **Checksum failure:** use the exact resource versions documented in
  [resources.md](resources.md); do not silently rename alternative
  references/manifests to bypass the checks.
- **Plugin unavailable / loader error:** confirm an amd64 image and the pinned
  plugin/bcftools pairing. The newest upstream binaries target a different
  version.
- **Existing output:** choose a new project code or move the previous output set
  aside after reviewing it.
- **Project lock exists:** check that no run is active. A force-killed container
  can leave `$PWD/.PROJECT_CODE.idat2vcf.lock`; remove that empty directory only
  after confirming the run is no longer active.
- **Conversion failed:** inspect the log and preserved hidden working directory.
  These intermediates can be removed manually when no longer needed.
