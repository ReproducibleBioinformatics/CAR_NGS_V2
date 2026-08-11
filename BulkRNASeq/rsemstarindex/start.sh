#!/bin/bash
DOCKER_NAME="docker4seq-rsemstarindex-v2"

NC='\033[0m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'
log_info() { [ "$QUIET" == "true" ] && return; echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} INFO]    ${1}${NC}"; }
log_step() { [ "$QUIET" == "true" ] && return; echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} PROCESS] ${1}${NC}"; }
log_warn() { [ "$QUIET" == "true" ] && return; echo -e "${ORANGE}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} WARNING] ${1}${NC}"; }
log_success() { [ "$QUIET" == "true" ] && return; echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} SUCCESS] ${1}${NC}"; }
log_error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} ERROR]   ${1}${NC}"; }
log_sep() { [ "$QUIET" == "true" ] && return; echo -e "${2:-$CYAN}$(printf '%0.s'${1:-=} {1..100})${NC}"; }

show_usage() {
    log_sep "-" "$YELLOW"
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  $0 <results> <fastafile> <gtffile> <filter> <chrom_pattern> <threads> <quiet>"
    echo ""
    echo -e "${YELLOW}Arguments (all mandatory):${NC}"
    echo -e "  ${CYAN}results${NC}       Output directory for pipeline results"
    echo -e "  ${CYAN}fastafile${NC}     Path to the input genome FASTA file (.fa or .fa.gz)"
    echo -e "  ${CYAN}gtffile${NC}       Path to the input gene annotation GTF file (.gtf or .gtf.gz)"
    echo -e "  ${CYAN}filter${NC}        Filtering mode ('none', 'all', 'mito', 'chrom')"
    echo -e "  ${CYAN}chrom_pattern${NC} Chromosome regex filter pattern (use \"\" when not needed, e.g., 'chr1' or '(1)')"
    echo -e "  ${CYAN}threads${NC}       Number of parallel threads (positive integer)"
    echo -e "  ${CYAN}quiet${NC}         Suppress processing log messages: 'true' or 'false'"
    log_sep "-" "$YELLOW"
}

# ------- Argument Checking ------- #
# All arguments are mandatory: always use -ne <N> for an exact count check.
# Do NOT use -lt <N> / optional trailing arguments - every parameter must be
# explicitly passed by the caller, even if empty ("" for chrom_pattern when
# not needed).
if [ "$#" -ne 7 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_usage
    exit 1
fi

# ------- Positional Arguments Assignment ------- #
results="${1}"
fastafile="${2}"
gtffile="${3}"
filter="${4}"
chrom_pattern="${5}"
threads="${6}"
quiet="${7}"

# ------- Validate Quiet Parameter (upfront, required for logging) ------- #
# Always validate "quiet" BEFORE printing anything else, so that an invalid
# value fails immediately without emitting a partial/misleading context block.
if [ "$quiet" != "true" ] && [ "$quiet" != "false" ]; then
    log_error "The quiet parameter must be 'true' or 'false' (provided: '$quiet')"
    exit 1
fi
QUIET="$quiet"

# ------- Print Pipeline Execution Context ------- #
log_sep "=" "$CYAN"
log_info "Pipeline Execution Context:"
echo -e "  ${CYAN}Docker Container:${NC} ${GREEN}${DOCKER_NAME}${NC}"
echo -e "  ${CYAN}Results Dir     :${NC} ${YELLOW}${results}${NC}"
echo -e "  ${CYAN}FASTA File      :${NC} ${YELLOW}${fastafile}${NC}"
echo -e "  ${CYAN}GTF File        :${NC} ${YELLOW}${gtffile}${NC}"
echo -e "  ${CYAN}Filter Mode     :${NC} ${YELLOW}${filter}${NC}"
echo -e "  ${CYAN}Chr Pattern     :${NC} '${YELLOW}${chrom_pattern}${NC}'"
echo -e "  ${CYAN}Threads         :${NC} ${YELLOW}${threads}${NC}"
echo -e "  ${CYAN}Quiet Mode      :${NC} ${YELLOW}${quiet}${NC}"
log_sep "=" "$CYAN"
log_info "Initializing RSEM/STAR Index Pipeline Wrapper"

# ------- Validate Threads Parameter ------- #
log_step "Validating parameters and environment..."
if ! [[ "$threads" =~ ^[0-9]+$ ]] || [ "$threads" -le 0 ]; then
    log_error "The threads parameter must be a positive integer (provided: '$threads')"
    exit 1
fi
export OMP_NUM_THREADS=$threads

# ------- Optimize Threads Allocation ------- #
max_cores=$(nproc)
if [ "$threads" -gt "$max_cores" ]; then
    log_warn "Requested threads ($threads) exceed available CPU cores ($max_cores). Capping allocation to $max_cores."
    threads=$max_cores
fi

# ------- Check Results Directory ------- #
if [ ! -d "$results" ]; then
    log_error "Results directory '$results' does not exist."
    exit 1
fi
if [ -n "$(find "$results" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    log_error "Results directory '$results' is not empty. Terminating pipeline to prevent overwriting existing data."
    exit 1
fi

# ------- Check Input Files ------- #
if [ -z "$fastafile" ] || [ ! -f "$fastafile" ]; then
    log_error "FASTA file parameter is empty or the file '$fastafile' does not exist."
    exit 1
fi
if [ -z "$gtffile" ] || [ ! -f "$gtffile" ]; then
    log_error "GTF file parameter is empty or the file '$gtffile' does not exist."
    exit 1
fi

# ------- Validate Filter Parameter ------- #
case "$filter" in
    none|all|mito|chrom) ;;
    *)
        log_error "Unsupported filter '$filter'. Allowed values: 'none', 'all', 'mito', 'chrom'."
        exit 1
        ;;
esac

# ==============================================================================
# EXIT CODE SCHEME
# exit 1 -> usage / argument / input / metadata validation errors (everything above this line)
# The three external tools invoked below (remove_mitochondrion.R,
# filter_chromosomes.R, rsem-prepare-reference) do NOT follow a simple
# incrementing exit-N-per-tool scheme, because the original business logic
# combines them differently and is left unchanged here:
#   - remove_mitochondrion.R / filter_chromosomes.R: any real failure of
#     either sets overall_status=1 and aborts before RSEM (status 3 from
#     remove_mitochondrion.R is treated as a non-fatal warning, not a
#     failure).
#   - rsem-prepare-reference: its own exit code is propagated verbatim via
#     "exit $overall_status" (not remapped to a fixed scheme value), since
#     the exact code may carry diagnostic meaning.
# ==============================================================================

# ------- Step 1: Decompress Input Files Upfront ------- #
log_step "Decompressing input files if needed..."
tmp_decomp_dir="${results}/_tmp_decomp"
mkdir -p "$tmp_decomp_dir"

target_gtf="${tmp_decomp_dir}/annotation.gtf"
target_fasta="${tmp_decomp_dir}/genome.fa"

if [[ "$gtffile" == *.gz ]]; then
    log_info "Decompressing GTF file..."
    gunzip -c "$gtffile" > "$target_gtf"
else
    cp "$gtffile" "$target_gtf"
fi

if [[ "$fastafile" == *.gz ]]; then
    log_info "Decompressing FASTA file..."
    gunzip -c "$fastafile" > "$target_fasta"
else
    cp "$fastafile" "$target_fasta"
fi

# ------- Step 2: Apply Filters on Decompressed Files ------- #
log_step "Applying requested filter (filter=$filter)..."
log_sep
overall_status=0

run_remove_mitochondrion() {
    log_info "-> Running remove_mitochondrion on $target_fasta"
    Rscript "/home/remove_mitochondrion.R" "$target_fasta" "$quiet"
    return $?
}

run_filter_chromosomes() {
    log_info "-> Running filter_chromosomes on $target_fasta"
    if [ -n "$chrom_pattern" ]; then
        Rscript "/home/filter_chromosomes.R" "$target_fasta" "$chrom_pattern" "$quiet"
    else
        Rscript "/home/filter_chromosomes.R" "$target_fasta" "" "$quiet"
    fi
    return $?
}

if [ "$filter" == "none" ]; then
    log_info "filter=none: skipping all filtering steps."
fi

if [ "$filter" == "all" ] || [ "$filter" == "mito" ]; then
    run_remove_mitochondrion
    status_r=$?
    if [ $status_r -eq 3 ]; then
        log_warn "remove_mitochondrion completed with status 3: No target chromosomes found for filtering."
    elif [ $status_r -ne 0 ]; then
        log_error "remove_mitochondrion filtering step failed with status $status_r."
        overall_status=1
    else
        log_success "Mitochondrion filtering completed successfully."
    fi
fi

if [ "$overall_status" -eq 0 ] && { [ "$filter" == "all" ] || [ "$filter" == "chrom" ]; }; then
    run_filter_chromosomes
    status_r=$?
    if [ $status_r -ne 0 ]; then
        log_error "filter_chromosomes filtering step failed with status $status_r."
        overall_status=1
    else
        log_success "Chromosome filtering completed successfully."
    fi
fi

if [ "$overall_status" -ne 0 ]; then
    log_error "One or more filtering steps failed. Aborting before RSEM reference preparation."
    rm -rf "$tmp_decomp_dir"
    exit "$overall_status"
fi

# ------- Step 3: Run RSEM Prepare Reference ------- #
log_step "Building RSEM/STAR genome index..."
log_sep

"rsem-prepare-reference" \
    -p "$threads" \
    --star \
    --star-path /usr/local/bin/ \
    --gtf "$target_gtf" \
    "$target_fasta" \
    "${results}/genome"

overall_status=$?

# ------- Clean Up Temporary Directory ------- #
rm -rf "$tmp_decomp_dir"

# ------- Final Output Check ------- #
if [ "$overall_status" -ne 0 ]; then
    log_sep
    log_error "rsem-prepare-reference failed. See errors above."
    log_error "Pipeline Terminated with Errors."
    exit $overall_status
fi

log_sep
log_info "Outputs generated in $results"
log_success "RSEM reference preparation completed successfully."
log_success "Pipeline Terminated Successfully."
