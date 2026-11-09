#!/usr/bin/env bash
# ==============================================================================
# Public sample data for idat2vcf
# ==============================================================================
# Description: Downloads one public Illumina IDAT pair from NCBI GEO, verifies
#              pinned SHA-256 checksums, and lays it out as an idat2vcf project.
# Usage: scripts/fetch-sample-data.sh [PROJECT_DIR]   (default: ./idat2vcf-sample)
# Source: GEO series GSE272121, sample GSM8393537 ("NHA, vial 1"): normal human
#         astrocytes, a commercial primary cell line. The chip carries every
#         Infinium GSA v3.0 bead address, so the GSA v3.0 bundle converts it.
# Result: PROJECT_DIR/idat_files/208358440099_R01C01_{Grn,Red}.idat
#         PROJECT_DIR/logs/idat2vcf/
# Requirements: bash, curl, gzip, sha256sum. Existing files are never replaced.
# ==============================================================================

set -Eeuo pipefail

GEO_BASE_URL='https://ftp.ncbi.nlm.nih.gov/geo/samples/GSM8393nnn/GSM8393537/suppl'
GEO_PREFIX='GSM8393537_'
SAMPLE_NAME='208358440099_R01C01'
declare -A GZ_SHA256=(
    [Grn]='049ecffade2051c2e4ca93d639f31e7c49672cc5524768c14bf0cc2a3d702212'
    [Red]='774557e0efa5c283fe9450799c10f64d56fd7c6da5242842ac8f96639a6a7dae'
)

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

case "${1:-}" in
    -h|--help)
        printf 'Usage: %s [PROJECT_DIR]\n' "$0"
        printf 'Download the public GSE272121 sample IDAT pair into PROJECT_DIR/idat_files/\n'
        printf '(default PROJECT_DIR: ./idat2vcf-sample).\n'
        exit 0
        ;;
esac
(( $# <= 1 )) || fail "Expected at most one argument: PROJECT_DIR"

for tool in curl gzip sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || fail "Required tool not found: $tool"
done

project_dir=${1:-idat2vcf-sample}
idat_dir="$project_dir/idat_files"
mkdir -p -- "$idat_dir" "$project_dir/logs/idat2vcf"

# Refuse before downloading if any target already exists.
for channel in Grn Red; do
    target="$idat_dir/${SAMPLE_NAME}_${channel}.idat"
    [[ ! -e $target ]] || fail "Refusing to replace existing file: $target"
done

staging=$(mktemp -d "$project_dir/.fetch-sample.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT

for channel in Grn Red; do
    archive="${GEO_PREFIX}${SAMPLE_NAME}_${channel}.idat.gz"
    printf 'Downloading %s\n' "$archive"
    curl --fail --location --silent --show-error --retry 3 \
        --output "$staging/$archive" "$GEO_BASE_URL/$archive"
    printf '%s  %s\n' "${GZ_SHA256[$channel]}" "$staging/$archive" | sha256sum --check --strict --quiet \
        || fail "Checksum mismatch for $archive"
    # gtc2vcf derives sample IDs from filenames and allows at most two underscores,
    # so the GEO accession prefix is dropped.
    gzip --decompress --stdout -- "$staging/$archive" > "$staging/${SAMPLE_NAME}_${channel}.idat"
done

for channel in Grn Red; do
    mv --no-clobber -- "$staging/${SAMPLE_NAME}_${channel}.idat" "$idat_dir/"
    [[ ! -e "$staging/${SAMPLE_NAME}_${channel}.idat" ]] \
        || fail "Refusing to replace existing file: $idat_dir/${SAMPLE_NAME}_${channel}.idat"
done

printf 'Sample IDAT pair ready in %s\n' "$idat_dir"
