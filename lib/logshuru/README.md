# Bundled first-party library: logshuru

Both [idat2vcf](https://github.com/mubeenomics/idat2vcf) and
[logshuru](https://github.com/mubeenomics/logshuru) are created by Mohammed Mubeen
Shaikh under [mubeenomics](https://github.com/mubeenomics). logshuru is bundled here
as a version-pinned first-party library, with its own MIT license.

- Project: <https://github.com/mubeenomics/logshuru>
- Version: **v2.0.0**
- Tagged commit: `494e69ce4f3199ec04e6e6c29e283d06fd09713d`
- Script artifact: <https://github.com/mubeenomics/logshuru/releases/download/v2.0.0/logshuru.sh>
- License source: <https://github.com/mubeenomics/logshuru/blob/v2.0.0/LICENSE>
- License: MIT, reproduced in `LICENSE`.

`logshuru.sh` is an unmodified logshuru release artifact. Checksums for the script
and license are recorded in `SHA256SUMS`. From this directory, verify with:

```bash
sha256sum -c SHA256SUMS
```

The pipeline sources this library directly from a checkout, or from
`/usr/local/share/idat2vcf/logshuru/logshuru.sh` inside the image. The Docker build
verifies the checksums before accepting the installation. No runtime download is
required. Update the pinned version, provenance, checksums, and license together.
