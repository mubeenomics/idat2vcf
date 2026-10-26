# ==============================================================================
# Docker Image for Infinium GSA v3.0 IDAT to GRCh38 VCF Conversion
# ==============================================================================
# Build: docker build --platform linux/amd64 -f idat2vcf.Dockerfile -t idat2vcf:local .
# Requires the local resource TAR and BuildKit; see README.md for runtime mounts.
# Bundled plugins are Linux x86_64 binaries built for bcftools 1.20.

# Use Miniforge (conda-forge) as the pinned base image (Ubuntu 24.04 "Noble",
# conda 26.9.4 / mamba 2.9.0 at the time of validation).
FROM condaforge/miniforge3:26.9.4-0

# Add metadata labels.
LABEL author="Mubeen" \
      description="Convert Infinium GSA v3.0 IDAT files to indexed GRCh38 VCF" \
      version="1.0"

# Check the supported architecture, install the matching bcftools version using
# strict conda-forge/bioconda priority, and clean package caches in the same layer.
RUN test "$(uname -m)" = x86_64 && \
    mamba install -n base --override-channels -c conda-forge -c bioconda \
        --strict-channel-priority bcftools=1.20 -y && \
    conda clean -afy

# Give bcftools an explicit plugin search directory.
ENV BCFTOOLS_PLUGINS=/opt/idat2vcf/plugins
# Set the working directory for the extracted reference and array resources.
WORKDIR /idat2vcf_resources

# Bind the local bundle only for this build step: the archive is not stored in
# an image layer. Docker BuildKit is required (default in current Docker).
COPY resources.sha256 /idat2vcf_resources/resources.sha256
# Extract only the expected resources, validate every checksum, install the
# plugins, and verify discovery/help output before accepting the image build.
RUN --mount=type=bind,source=idat2vcf.grch38.tar.gz,target=/tmp/resources.tar.gz \
    tar -xzf /tmp/resources.tar.gz --no-same-owner \
        GCA_000001405.15_GRCh38_no_alt_analysis_set.fna \
        GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.fai \
        GSA-24v3-0_A1_ClusterFile.egt GSA-24v3-0_A2.bpm GSA-24v3-0_A2.csv \
        gtc2vcf.so idat2gtc.so && \
    sha256sum -c resources.sha256 && \
    mkdir -p "$BCFTOOLS_PLUGINS" && \
    mv gtc2vcf.so idat2gtc.so "$BCFTOOLS_PLUGINS/" && \
    bcftools plugin -l | grep -Fx idat2gtc && \
    bcftools plugin -l | grep -Fx gtc2vcf && \
    (bcftools +idat2gtc -h 2>&1 || true) | grep -F 'Usage: bcftools +idat2gtc' && \
    (bcftools +gtc2vcf -h 2>&1 || true) | grep -F 'Usage: bcftools +gtc2vcf'

# Install the bundled first-party logger with its MIT license/provenance and verify.
# Keeping it inside the image avoids any dependency download during conversion.
COPY lib/logshuru/ /usr/local/share/idat2vcf/logshuru/
RUN cd /usr/local/share/idat2vcf/logshuru && sha256sum -c SHA256SUMS

# Install the executable pipeline and preserve upstream dependency license notices.
COPY --chmod=755 idat2vcf.docker.sh /usr/local/bin/idat2vcf
COPY THIRD_PARTY_NOTICES.md /usr/local/share/licenses/idat2vcf/THIRD_PARTY_NOTICES.md
# Run conversion directly when given a project code; show usage when none is given.
# For an interactive shell, override the entrypoint with --entrypoint bash.
ENTRYPOINT ["/usr/local/bin/idat2vcf"]
CMD ["--help"]
