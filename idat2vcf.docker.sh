#!/usr/bin/env bash
# ==============================================================================
# IDAT to VCF Conversion Script for Docker Container
# ==============================================================================
# Description: Converts Illumina Infinium GSA v3.0 IDAT files to indexed GRCh38 VCF
#              using the bcftools idat2gtc and gtc2vcf plugins.
# Usage: ./idat2vcf.docker.sh [--verbose] <PROJECT_CODE>
#        docker run [mount options] idat2vcf:local [--verbose] <PROJECT_CODE>
# Requirements: bcftools + plugins, matching BPM/CSV/EGT files, FASTA + .fai index.
#               Bundled first-party logshuru v2.0.0 supplies event logging.
#               The Docker build installs and verifies these resources once.
# Inputs:  ${DATA_DIR:-/data}/idat_files (paired *_Grn.idat and *_Red.idat files).
# Outputs: <PROJECT_CODE>.vcf.gz, .vcf.gz.csi, and .extra.tsv in DATA_DIR;
#          timestamped logs in ${LOG_DIR:-/container_logs}.
# Console: Final status only by default; --verbose also streams the full run log.
# ==============================================================================

# Propagate errors through functions and pipelines; reject undefined variables.
set -Eeuo pipefail

# ==============================================================================
# CONFIGURATION AND ARGUMENT VALIDATION
# ==============================================================================

# Display usage without requiring resources, mounted inputs, or logging access.
usage() {
    printf 'Usage: %s [--verbose] <PROJECT_CODE>\n' "$0"
    printf '  --verbose  Stream pipeline events and tool output to the terminal.\n'
    printf 'By default, save the run log and print only the final success/failure status.\n'
    printf 'PROJECT_CODE must start with a letter or digit and contain only letters, digits, dot, underscore, or hyphen.\n'
}

# Validate arguments before creating files; keep the project code a safe basename.
VERBOSE=false
PROJECT_CODE=''
while (( $# > 0 )); do
    case "$1" in
        --verbose) VERBOSE=true ;;
        --help|-h) usage; exit 0 ;;
        --)
            shift
            if [[ $# != 1 || -n $PROJECT_CODE ]]; then
                usage >&2
                exit 1
            fi
            PROJECT_CODE=$1
            break
            ;;
        -*)
            printf 'ERROR: Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
        *)
            if [[ -n $PROJECT_CODE || -z $1 ]]; then
                usage >&2
                exit 1
            fi
            PROJECT_CODE=$1
            ;;
    esac
    shift
done
if [[ ! $PROJECT_CODE =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
    usage >&2
    exit 1
fi

# Define data/log locations. Environment overrides support alternative mounts.
DATA_DIR=${DATA_DIR:-/data}
LOG_DIR=${LOG_DIR:-/container_logs}
IDAT2VCF_RESOURCES_DIR=${IDAT2VCF_RESOURCES_DIR:-/idat2vcf_resources}
IDAT_INPUT_DIR="${DATA_DIR}/idat_files"
# Use the exact manifest, cluster, and reference set verified during the build.
BPM_MANIFEST_FILE="${IDAT2VCF_RESOURCES_DIR}/GSA-24v3-0_A2.bpm"
CSV_MANIFEST_FILE="${IDAT2VCF_RESOURCES_DIR}/GSA-24v3-0_A2.csv"
EGT_CLUSTER_FILE="${IDAT2VCF_RESOURCES_DIR}/GSA-24v3-0_A1_ClusterFile.egt"
REFERENCE_GENOME="${IDAT2VCF_RESOURCES_DIR}/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna"

# ==============================================================================
# LOGGING AND VALIDATION FUNCTIONS
# ==============================================================================

# Reject non-absolute HOST_LOG_DIR overrides before creating any files.
if [[ -n ${HOST_LOG_DIR:-} && $HOST_LOG_DIR != /* ]]; then
    printf 'FAILED: %s. HOST_LOG_DIR must be an absolute path: %s\n' \
        "$PROJECT_CODE" "$HOST_LOG_DIR" >&2
    exit 1
fi

# Create the directory before the first message and use a unique log per run.
if ! mkdir -p -- "$LOG_DIR"; then
    printf 'FAILED: %s. Cannot create log directory: %s\n' "$PROJECT_CODE" "$LOG_DIR" >&2
    exit 1
fi
if ! LOG_FILE=$(mktemp "${LOG_DIR}/${PROJECT_CODE}_$(date -u +%Y%m%dT%H%M%SZ)_XXXXXX.log"); then
    printf 'FAILED: %s. Cannot create a run log in: %s\n' "$PROJECT_CODE" "$LOG_DIR" >&2
    exit 1
fi
# mktemp creates owner-only files; make the run log group/other-readable so
# colleagues on shared storage can read it alongside the outputs it describes.
chmod 644 -- "$LOG_FILE" || :

# Show the host system log path in messages. An explicit HOST_LOG_DIR is the
# reliable override and the documented setting; otherwise this is a best-effort
# read of the bind-mount source in /proc/self/mountinfo. The mountinfo root is
# filesystem-relative and cannot be resolved for every mount layout, so
# unresolvable cases fall back to the container path.
LOG_HOST_DIR=${HOST_LOG_DIR:-}
if [[ -z $LOG_HOST_DIR ]]; then
    LOG_HOST_DIR=$(awk -v mount_point="$LOG_DIR" '$5 == mount_point {print $4; exit}' \
        /proc/self/mountinfo 2>/dev/null || true)
fi
if [[ -z $LOG_HOST_DIR || $LOG_HOST_DIR == / ]]; then
    LOG_HOST_DIR=$LOG_DIR
fi
LOG_HOST_DIR=${LOG_HOST_DIR%/}
LOG_DISPLAY_PATH="${LOG_HOST_DIR}/${LOG_FILE##*/}"

# Preserve the original console streams for the final, unfiltered status summary.
# Quiet mode writes directly to the log; verbose mode also relays through tee.
exec {CONSOLE_OUT}>&1 {CONSOLE_ERR}>&2
LOG_CAPTURE_PID=''
if [[ $VERBOSE == true ]]; then
    exec > >(tee -a "$LOG_FILE" >&"$CONSOLE_OUT") 2>&1
    LOG_CAPTURE_PID=$!
else
    exec >>"$LOG_FILE" 2>&1
fi
LOGGER_READY=false

# Configure logshuru before sourcing. Shell capture owns the run log, so disable
# the logger's duplicate file sink. Raw bcftools diagnostics remain unfiltered.
export LOG_LEVEL=${LOG_LEVEL:-PROCESS}
export LOGSHURU_OUTPUT=${LOGSHURU_OUTPUT:-stderr}
export LOGSHURU_COLOR=${LOGSHURU_COLOR:-never}
export LOGSHURU_FORMAT=${LOGSHURU_FORMAT:-text}
export LOGSHURU_TZ=${LOGSHURU_TZ:-UTC}
export LOGSHURU_FILE=''
# Log a fatal error and exit through the cleanup handler.
# An ERROR event does not itself exit; logger failure must not prevent our exit.
fail() {
    log ERROR "$*" || :
    exit 1
}
# Require regular, readable, nonempty resource and output files.
validate_file() {
    [[ -f $1 && -r $1 && -s $1 ]] || fail "Required file missing, empty, or unreadable: $1"
}

# ==============================================================================
# FAILURE HANDLING AND RUN-OWNED CLEANUP
# ==============================================================================

WORK_DIR=''
LOCK_DIR=''
# Remove only this run's intermediates on success; retain them for debugging on
# failure. Release only a project lock successfully acquired by this process.
cleanup() {
    local status=$?
    trap - EXIT ERR
    if [[ -n $WORK_DIR && -d $WORK_DIR ]]; then
        if (( status == 0 )); then
            if ! rm -rf -- "$WORK_DIR"; then
                status=1
                log ERROR "Failed to clean working directory: $WORK_DIR" || :
            fi
        else
            log ERROR "Run failed (exit $status). Intermediates retained: $WORK_DIR" || :
        fi
    fi
    if [[ -n $LOCK_DIR ]]; then
        if ! rmdir -- "$LOCK_DIR"; then
            if (( status == 0 )); then
                status=1
            fi
            log ERROR "Failed to release project lock: $LOCK_DIR" || :
        fi
    fi

    # Close both pipe writers before waiting, so verbose output is fully drained
    # before the completion event and final summary. Capture failure must not
    # replace a tool error.
    exec 1>&"$CONSOLE_OUT" 2>&"$CONSOLE_ERR"
    if [[ -n $LOG_CAPTURE_PID ]]; then
        local capture_status=0
        wait "$LOG_CAPTURE_PID" || capture_status=$?
        if (( status == 0 && capture_status != 0 )); then
            status=$capture_status
        fi
    fi

    # Report completion only after working-directory cleanup, lock release, and
    # log draining. Initialization can fail before the logger is ready. The
    # formatted event goes only to the run log for every logger routing mode;
    # the console keeps one summary.
    if (( status == 0 )) && [[ $LOGGER_READY == true ]]; then
        log SUCCESS "Completed project: $PROJECT_CODE" >>"$LOG_FILE" 2>&1 || status=1
    fi

    if (( status == 0 )); then
        printf 'SUCCESS: %s completed. Log: %s\n' "$PROJECT_CODE" "$LOG_DISPLAY_PATH" || status=1
    else
        printf 'FAILED: %s (exit %s). Log: %s\n' "$PROJECT_CODE" "$status" "$LOG_DISPLAY_PATH" >&2 || :
    fi
    exit "$status"
}
# Preserve nonzero status and run cleanup after command failures or interruptions.
# Logging in traps is best-effort so logger failures cannot mask the original
# command status or prevent lock release and intermediate preservation.
trap cleanup EXIT
# Initialize only after installing the EXIT handler, so invalid configuration or
# a missing library produces a quiet-mode failure summary pointing to its log.
# Locate the pinned logger beside a checkout, or at its installed container path.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LOGGER_PATH="${SCRIPT_DIR}/lib/logshuru/logshuru.sh"
if [[ ! -r $LOGGER_PATH ]]; then
    LOGGER_PATH=/usr/local/share/idat2vcf/logshuru/logshuru.sh
fi
# shellcheck source=lib/logshuru/logshuru.sh
source "$LOGGER_PATH" || exit 1
LOGGER_READY=true
trap 'log ERROR "Command failed at line $LINENO (exit $?)" || :' ERR

# ==============================================================================
# INTERRUPTION HANDLING
# ==============================================================================

# docker stop sends SIGTERM only to the container init, which forwards it to
# this shell; the conversion pipeline children would otherwise keep running and
# force a timeout kill without any bookkeeping. Track the conversion as a
# background subshell so interruptions can terminate it promptly.
CONVERSION_PID=''

# List the direct child PIDs of a process without requiring pgrep/procps.
list_child_pids() {
    local children_file
    for children_file in /proc/"$1"/task/*/children; do
        [[ -r $children_file ]] || continue
        tr ' ' '\n' <"$children_file"
    done
}

# Terminate a process and all of its descendants, children first, so pipeline
# grandchildren stop before their parents exit.
terminate_tree() {
    local pid=$1 grandchild
    local -a grandchildren=()
    mapfile -t grandchildren < <(list_child_pids "$pid")
    for grandchild in "${grandchildren[@]}"; do
        [[ -n $grandchild ]] || continue
        terminate_tree "$grandchild"
    done
    kill -TERM "$pid" 2>/dev/null || :
}

# Terminate the conversion pipeline on INT/TERM, then let the EXIT handler
# retain intermediates, release the project lock, and print the final summary.
terminate_run() {
    local signal_status=$1 signal_message=$2
    trap - INT TERM ERR
    log WARNING "$signal_message" || :
    if [[ -n $CONVERSION_PID ]]; then
        terminate_tree "$CONVERSION_PID"
    fi
    if [[ -n $LOG_CAPTURE_PID ]]; then
        kill -TERM "$LOG_CAPTURE_PID" 2>/dev/null || :
    fi
    exit "$signal_status"
}
trap 'terminate_run 130 "Interrupted"' INT
trap 'terminate_run 143 "Terminated"' TERM

# ==============================================================================
# FILE, DIRECTORY, AND PLUGIN VALIDATION
# ==============================================================================

log INFO "Starting project: $PROJECT_CODE; log: $LOG_DISPLAY_PATH"
log PROCESS 'Validating required files, directories, and plugins'
command -v bcftools >/dev/null || fail 'bcftools is not on PATH'
[[ -d $DATA_DIR && -w $DATA_DIR ]] || fail "Data directory missing or unwritable: $DATA_DIR"
[[ -d $IDAT_INPUT_DIR && -r $IDAT_INPUT_DIR ]] || fail "IDAT directory missing or unreadable: $IDAT_INPUT_DIR"
for file in "$BPM_MANIFEST_FILE" "$CSV_MANIFEST_FILE" "$EGT_CLUSTER_FILE" \
    "$REFERENCE_GENOME" "${REFERENCE_GENOME}.fai"; do
    validate_file "$file"
done
# Verify both plugins load before starting genotype conversion.
plugins=$(bcftools plugin -l)
for plugin in idat2gtc gtc2vcf; do
    [[ $'\n'"$plugins"$'\n' == *$'\n'"$plugin"$'\n'* ]] || fail "bcftools plugin unavailable: $plugin"
done
# Capture version information without printing the full copyright banner.
bcftools_version=$(bcftools --version-only)
log INFO "Using bcftools ${bcftools_version}"

# ==============================================================================
# OUTPUT PROTECTION AND INPUT CHECKS
# ==============================================================================

# mkdir provides an atomic lock for cooperating runs sharing this output directory.
lock_path="${DATA_DIR}/.${PROJECT_CODE}.idat2vcf.lock"
mkdir -- "$lock_path" || fail "Project lock exists or cannot be created: $lock_path"
LOCK_DIR=$lock_path
# Define final outputs and refuse to overwrite any part of an existing set.
FINAL_VCF_FILE="${DATA_DIR}/${PROJECT_CODE}.vcf.gz"
EXTRA_INFO_FILE="${DATA_DIR}/${PROJECT_CODE}.extra.tsv"
for file in "$FINAL_VCF_FILE" "${FINAL_VCF_FILE}.csi" "$EXTRA_INFO_FILE"; do
    [[ ! -e $file && ! -L $file ]] || fail "Refusing to replace existing output: $file"
done

# Preflight: fail fast unless every top-level *_Grn.idat has a same-directory
# matching *_Red.idat and the counts agree, so mistakes surface before
# genotyping starts. The search is top-level only because the upstream plugin
# does not recurse into subdirectories.
grn_count=$(find "$IDAT_INPUT_DIR" -maxdepth 1 -type f -name '*_Grn.idat' -printf '. ' | wc -w)
red_count=$(find "$IDAT_INPUT_DIR" -maxdepth 1 -type f -name '*_Red.idat' -printf '. ' | wc -w)
(( grn_count > 0 )) || fail "No *_Grn.idat files found in $IDAT_INPUT_DIR"
(( grn_count == red_count )) || \
    fail "Unpaired IDAT files: $grn_count _Grn vs $red_count _Red in $IDAT_INPUT_DIR"
while IFS= read -r grn_file; do
    red_file=${grn_file%_Grn.idat}_Red.idat
    [[ -f $red_file ]] || fail "Missing matching Red IDAT for: $grn_file"
done < <(find "$IDAT_INPUT_DIR" -maxdepth 1 -type f -name '*_Grn.idat')
idat_count=$(find "$IDAT_INPUT_DIR" -maxdepth 1 -type f -name '*.idat' -printf '. ' | wc -w)
if (( idat_count != grn_count + red_count )); then
    naming_note="$((idat_count - grn_count - red_count)) .idat file(s) do not follow the _Grn/_Red naming and are ignored"
    log WARNING "$naming_note" || :
    printf 'NOTE: %s. See: %s\n' "$naming_note" "$LOG_DISPLAY_PATH" >&"$CONSOLE_ERR" || :
fi
log INFO "Found $grn_count paired IDAT samples ($((grn_count + red_count)) files)"

# ==============================================================================
# IDAT TO GTC CONVERSION
# ==============================================================================

# Isolate each run so pre-existing GTC files cannot enter the conversion or cleanup.
WORK_DIR=$(mktemp -d "${DATA_DIR}/.${PROJECT_CODE}.idat2vcf.XXXXXX")
GTC_OUTPUT_DIR="${WORK_DIR}/gtc_files"
mkdir -- "$GTC_OUTPUT_DIR"

# Run both conversion stages, staged validation, and publication in a background
# subshell. wait() in the parent lets the INT/TERM handlers above terminate the
# whole pipeline promptly while preserving this run's bookkeeping.
run_conversion() {
    log DEBUG "Working directory: $WORK_DIR"
    log PROCESS 'Starting IDAT to GTC conversion'
    bcftools +idat2gtc \
        --bpm "$BPM_MANIFEST_FILE" \
        --egt "$EGT_CLUSTER_FILE" \
        --idats "$IDAT_INPUT_DIR" \
        --output "$GTC_OUTPUT_DIR"
    # Verify that the genotyping stage actually generated GTC files.
    gtc_count=$(find "$GTC_OUTPUT_DIR" -type f -name '*.gtc' -printf '. ' | wc -w)
    (( gtc_count > 0 )) || fail 'No GTC files generated'
    log INFO "Generated $gtc_count GTC files"

    # Stage results in the working directory; publish them only after validation.
    STAGED_VCF="${WORK_DIR}/${PROJECT_CODE}.vcf.gz"
    STAGED_EXTRA="${WORK_DIR}/${PROJECT_CODE}.extra.tsv"
    # Stream uncompressed BCF between stages to avoid intermediate serialization.
    # norm -c x excludes reference-mismatching records; --write-index creates the CSI.
    log PROCESS 'Starting GTC to VCF conversion, sorting, and normalization'
    bcftools +gtc2vcf \
        --no-version -Ou \
        --bpm "$BPM_MANIFEST_FILE" \
        --csv "$CSV_MANIFEST_FILE" \
        --egt "$EGT_CLUSTER_FILE" \
        --gtcs "$GTC_OUTPUT_DIR" \
        --fasta-ref "$REFERENCE_GENOME" \
        --extra "$STAGED_EXTRA" |
        bcftools sort -Ou -T "${WORK_DIR}/sort.XXXXXX" |
        bcftools norm --no-version -Oz -c x -f "$REFERENCE_GENOME" \
            -o "$STAGED_VCF" --write-index

    # Check all expected artifacts, VCF header readability, and index readability.
    for file in "$STAGED_VCF" "${STAGED_VCF}.csi" "$STAGED_EXTRA"; do
        validate_file "$file"
    done
    bcftools view -h "$STAGED_VCF" >/dev/null
    # Capture the indexed record count instead of printing a bare number.
    indexed_records=$(bcftools index -n "$STAGED_VCF")
    log DEBUG "Indexed records: $indexed_records"
    # Guard against a silently wrong reference/manifest pairing: the validated
    # count for this exact bundle is 653,817. A deviation is flagged on the
    # console as well as in the log (it would otherwise be invisible in quiet
    # mode); with EXPECTED_VCF_RECORDS_STRICT set it fails the run before
    # publication.
    expected_records=${EXPECTED_VCF_RECORDS:-653817}
    if [[ ! $expected_records =~ ^[0-9]+$ ]]; then
        fail "EXPECTED_VCF_RECORDS must be a non-negative integer: $expected_records"
    fi
    if (( indexed_records != expected_records )); then
        deviation_note="Indexed record count $indexed_records differs from the validated count $expected_records; verify the reference/manifest pairing"
        log WARNING "$deviation_note; see this log for details" || :
        printf 'NOTE: %s. See: %s\n' "$deviation_note" "$LOG_DISPLAY_PATH" >&"$CONSOLE_ERR" || :
        if [[ -n ${EXPECTED_VCF_RECORDS_STRICT:-} ]]; then
            fail "$deviation_note (EXPECTED_VCF_RECORDS_STRICT is set)"
        fi
    fi
    # Publish only validated files. Existing outputs are checked while holding the lock.
    mv -- "$STAGED_EXTRA" "$EXTRA_INFO_FILE"
    mv -- "${STAGED_VCF}.csi" "${FINAL_VCF_FILE}.csi"
    mv -- "$STAGED_VCF" "$FINAL_VCF_FILE"
    log INFO "Outputs: $FINAL_VCF_FILE; ${FINAL_VCF_FILE}.csi; $EXTRA_INFO_FILE"
}
run_conversion &
CONVERSION_PID=$!
wait "$CONVERSION_PID"
# The EXIT handler cleans up, logs completion, and prints the final console status.
