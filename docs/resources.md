# Resource provenance and preparation

## Exact supported bundle

`idat2vcf.grch38.tar.gz` must contain these regular files directly at its root:

| File | Unpacked bytes | Source |
|---|---:|---|
| `GCA_000001405.15_GRCh38_no_alt_analysis_set.fna` | 3144230986 | NCBI GRCh38 no-alt |
| `GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.fai` | 7804 | Matching FASTA index |
| `GSA-24v3-0_A1_ClusterFile.egt` | 113375118 | Illumina GSA v3.0 |
| `GSA-24v3-0_A2.bpm` | 113522162 | Illumina GSA v3.0 A2 |
| `GSA-24v3-0_A2.csv` | 284225383 | Illumina GSA v3.0 A2, GRCh38 |
| `gtc2vcf.so` | 440600 | gtc2vcf 1.20-20240927, Linux x86_64 |
| `idat2gtc.so` | 408120 | gtc2vcf 1.20-20240927, Linux x86_64 |

SHA-256 checksums for each unpacked file are in [`resources.sha256`](../resources.sha256).
They fingerprint the supplied bundle; except for the plugins, they have not been
independently compared against new downloads from the providers.

## Reference

[NCBI source directory](https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/000/001/405/GCA_000001405.15_GRCh38/seqs_for_alignment_pipelines.ucsc_ids/)

Download `GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.gz`, decompress it,
and obtain the matching `.fna.fai` file, or generate it with `samtools faidx`.
This is the UCSC-ID no-alt reference also used in the upstream gtc2vcf examples.

The supplied index has been checked against the actual FASTA: all 195 sequence
names, lengths, offsets, and line widths match.

The alternative
[NCBI GRCh38.p14 directory](https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/001/405/GCF_000001405.40_GRCh38.p14/GRCh38_major_release_seqs_for_alignment_pipelines/)
is another provider source, but is not the reference used by this bundle.
Supporting it requires an explicit resource/configuration update and validation.

## Array manifests and clusters

[Illumina Infinium Global Screening Array v3.0 product files](https://sapac.support.illumina.com/downloads/infinium-global-screening-array-v3-0-product-files.html)

Select the exact A2 manifest versions above, including the **GRCh38** CSV, and
the A1 cluster file. Unpack provider ZIP downloads before assembling the bundle.
The supplied CSV names `GSA-24v3-0_A2.bpm` as its descriptor and all **654,027**
assay records declare `GenomeBuild=38`. The BPM header identifies the A2 BPM;
the EGT header identifies GSA v3.0 and has 654,027 loci. These structural checks
support the intended pairing; real IDAT conversion remains the functional check.
The upstream plugin performs its normal manifest consistency checks at runtime.

Refer to Illumina's download terms for these resources. They are not included in
the Git repository.

## Plugins

- Source repository: <https://github.com/freeseek/gtc2vcf>
- Release page: <https://software.broadinstitute.org/software/gtc2vcf/>
- Exact binaries: <https://software.broadinstitute.org/software/gtc2vcf/gtc2vcf_1.20-20240927.zip>
- Corresponding source: <https://software.broadinstitute.org/software/gtc2vcf/gtc2vcf_1.20-20240927.tar.gz>

Both supplied `.so` files were compared by SHA-256 with this binary release and
match exactly. These are Linux x86_64 binaries compiled for **bcftools 1.20**.
Do not substitute the current latest release (which targets bcftools 1.22).

The upstream software is authored by Giulio Genovese and released under the MIT
license. Retain upstream copyright and license notices if redistributing binaries
or source; these are reproduced in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)
and copied into the image. Upstream asks users
to cite its website in publications using the tool.

## Assemble the local bundle

Place the seven files in a separate local staging directory. From that directory,
verify checksums using the repository's absolute path:

```bash
sha256sum -c /absolute/path/to/idat2vcf/resources.sha256
```

Then create the archive in the repository root (replace the absolute path):

```bash
tar -czf /absolute/path/to/idat2vcf/idat2vcf.grch38.tar.gz \
  GCA_000001405.15_GRCh38_no_alt_analysis_set.fna \
  GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.fai \
  GSA-24v3-0_A1_ClusterFile.egt \
  GSA-24v3-0_A2.bpm GSA-24v3-0_A2.csv \
  gtc2vcf.so idat2gtc.so
```

Compression settings and TAR timestamps can change the archive checksum, so the
build validates **unpacked file checksums**. Its build context explicitly includes
this archive, while `.gitignore` keeps it out of Git history.

The built image embeds these resources in its layers. Keep the image private;
do not push it to a public registry.

The base image and bcftools version are pinned, but the complete transitive conda
dependency set is not locked. This setup preserves the verified resource/plugin
pairing rather than guaranteeing bit-identical container rebuilds indefinitely.
