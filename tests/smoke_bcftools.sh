#!/usr/bin/env bash
# Flag-level smoke test for the real bcftools sort|norm|index stage used by the
# pipeline. Requires bcftools on PATH (any recent 1.x). It deliberately does NOT
# exercise the bundled gtc2vcf plugins; those are covered by the local
# integration validation with the pinned bcftools 1.20 build.
set -euo pipefail

command -v bcftools >/dev/null || {
    printf 'bcftools is not on PATH\n' >&2
    exit 1
}

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

# Synthetic reference: two 200 bp contigs written in 60-column lines so the
# FASTA index offsets and line widths are uniform.
python3 - "$work" <<'PY'
import sys
from pathlib import Path

work = Path(sys.argv[1])
seq = "".join("ACGT"[(i * 7) % 4] for i in range(200))
lines = "\n".join(seq[i:i + 60] for i in range(0, 200, 60))
(work / "ref.fa").write_text(f">chr1\n{lines}\n>chr2\n{lines}\n")

alt = "A" if seq[99] != "A" else "G"
records = [
    # (contig, pos, ref, alt): REF must match the reference to be retained.
    ("chr1", 100, seq[99], alt),
    ("chr1", 148, "T" if seq[147] != "T" else "A", alt),  # mismatching REF, dropped by -c x
    ("chr2", 50, seq[49], alt),  # unsorted on purpose
]
header = "##fileformat=VCFv4.2\n"
header += "##contig=<ID=chr1,length=200>\n##contig=<ID=chr2,length=200>\n"
header += "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"
rows = "".join(
    f"{contig}\t{pos}\trs{index}\t{ref}\t{record_alt}\t50\tPASS\t.\n"
    for index, (contig, pos, ref, record_alt) in enumerate(records, 1)
)
(work / "input.vcf").write_text(header + rows)
PY

bcftools view -Ob "$work/input.vcf" |
    bcftools sort -T "$work/sort.XXXXXX" -Ou |
    bcftools norm --no-version -c x -f "$work/ref.fa" -Oz \
        -o "$work/out.vcf.gz" --write-index 2>"$work/norm.log"

count=$(bcftools index -n "$work/out.vcf.gz")
(( count == 2 )) || {
    printf 'Expected 2 surviving records, got %s\n' "$count" >&2
    exit 1
}
bcftools view -h "$work/out.vcf.gz" >/dev/null
grep -E 'skipped:[[:space:]]*[0-9]+/0/0/0/[1-9]' "$work/norm.log" >/dev/null || {
    printf 'Expected the mismatching record to be reported as skipped\n' >&2
    exit 1
}
printf 'bcftools smoke test passed (2 records retained, 1 mismatch skipped)\n'
