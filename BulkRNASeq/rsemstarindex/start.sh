#!/bin/bash
DOCKER_NAME="docker4seq-rsemstarindex-v2"

NC='\033[0m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'
log_info() { [ "$QUIET" == "true" ] && return; echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} INFO]    ${1}${NC}"; }
log_step() { [ "$QUIET" == "true" ] && return; echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} PROCESS] ${1}${NC}"; }
log_warn() { echo -e "${ORANGE}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} WARNING] ${1}${NC}"; }
log_success() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} SUCCESS] ${1}${NC}"; }
log_error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} ERROR]   ${1}${NC}"; }
log_sep() { echo -e "${2:-$CYAN}$(printf '%0.s'${1:-=} {1..100})${NC}"; }

show_usage() {
    log_sep "-" "$YELLOW"
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  $0 <outDir> <fastafile> <gtffile> <filter> [threads] [chrom_pattern] [quiet]"
    echo ""
    echo -e "${YELLOW}Arguments:${NC}"
    echo -e "  ${CYAN}outDir${NC}         Output directory for pipeline results"
    echo -e "  ${CYAN}fastafile${NC}      Path to the input genome FASTA file (.fa or .fa.gz)"
    echo -e "  ${CYAN}gtffile${NC}        Path to the input gene annotation GTF file (.gtf or .gtf.gz)"
    echo -e "  ${CYAN}filter${NC}         Filtering mode ('none', 'all', 'mito', 'chrom')"
    echo -e "  ${CYAN}chrom_pattern${NC}  Chromosome regex filter pattern (Optional, e.g., 'chr1' or '(1)')"
    echo -e "  ${CYAN}threads${NC}        Number of parallel threads "    
    echo -e "  ${CYAN}quiet${NC}          Suppress processing log messages: 'true' or 'false'"
    log_sep "-" "$YELLOW"
}

# ------- Argument Checking ------- #
if [ "$#" -lt 4 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_usage
    exit 1
fi

outDir="${1}"
fastafile="${2}"
gtffile="${3}"
filter="${4}"
chrom_pattern="${5}"
threads="${6}"
quiet="${7}"

# ------- Validate quiet parameter upfront for logging ------- #
if [ "$quiet" != "true" ] && [ "$quiet" != "false" ]; then
    log_error "The quiet parameter must be 'true' or 'false' (provided: '$quiet')"
    exit 1
fi
QUIET="$quiet"

log_sep "=" "$CYAN"
log_info "Pipeline Execution Context:"
echo -e "  ${CYAN}Docker Container:${NC} ${GREEN}${DOCKER_NAME}${NC}"
echo -e "  ${CYAN}Results Dir     :${NC} ${YELLOW}${outDir}${NC}"
echo -e "  ${CYAN}FASTA File      :${NC} ${YELLOW}${fastafile}${NC}"
echo -e "  ${CYAN}GTF File        :${NC} ${YELLOW}${gtffile}${NC}"
echo -e "  ${CYAN}Filter Mode     :${NC} ${YELLOW}${filter}${NC}"
echo -e "  ${CYAN}Chr Pattern     :${NC} '${YELLOW}${chrom_pattern}${NC}'"
echo -e "  ${CYAN}Threads         :${NC} ${YELLOW}${threads}${NC}"
echo -e "  ${CYAN}Quiet Mode      :${NC} ${YELLOW}${quiet}${NC}"
log_sep "=" "$CYAN"
log_info "Initializing RSEM Reference Preparation Wrapper"

# ------- Validate threads parameter ------- #
log_step "Validating directory mounts and input parameters..."
if ! [[ "$threads" =~ ^[0-9]+$ ]] || [ "$threads" -le 0 ]; then
    log_error "The threads parameter must be a positive integer (provided: '$threads')"
    exit 1
fi

# ------- Optimize threads allocation ------- #
max_cores=$(nproc)
if [ "$threads" -gt "$max_cores" ]; then
    log_warn "Requested threads ($threads) exceed available CPU cores ($max_cores). Capping allocation to $max_cores."
    threads=$max_cores
fi

# ------- Check outDir exists and is empty ------- #
if [ ! -d "$outDir" ]; then
    log_error "Output directory '$outDir' does not exist."
    exit 1
fi
if [ -n "$(find "$outDir" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    log_error "Output directory '$outDir' is not empty. Terminating pipeline to prevent overwriting existing data."
    exit 1
fi

# ------- Check input files ------- #
if [ -z "$fastafile" ] || [ ! -f "$fastafile" ]; then
    log_error "FASTA file parameter is empty or the file '$fastafile' does not exist."
    exit 3
fi
if [ -z "$gtffile" ] || [ ! -f "$gtffile" ]; then
    log_error "GTF file parameter is empty or the file '$gtffile' does not exist."
    exit 3
fi

# ------- Check filter ------- #
case "$filter" in
    none|all|mito|chrom) ;;
    *)
        log_error "Unsupported filter '$filter'. Allowed values: 'none', 'all', 'mito', 'chrom'."
        exit 3
        ;;
esac

# ------- Step 1: Decompress files upfront ------- #
log_step "Decompressing input files if needed..."
tmp_decomp_dir="${outDir}/_tmp_decomp"
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
OVERALL_STATUS=0

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
    STATUS_R=$? 
    if [ $STATUS_R -eq 3 ]; then
        log_warn "remove_mitochondrion completed with status 3: No target chromosomes found for filtering."
    elif [ $STATUS_R -ne 0 ]; then
        log_error "remove_mitochondrion filtering step failed with status $STATUS_R."
        OVERALL_STATUS=1
    else
        log_success "Mitochondrion filtering completed successfully."
    fi    
fi

if [ "$OVERALL_STATUS" -eq 0 ] && { [ "$filter" == "all" ] || [ "$filter" == "chrom" ]; }; then
    run_filter_chromosomes
    STATUS_R=$? 
    if [ $STATUS_R -ne 0 ]; then
        log_error "filter_chromosomes filtering step failed with status $STATUS_R."
        OVERALL_STATUS=1
    else
        log_success "Chromosome filtering completed successfully."
    fi
fi

if [ "$OVERALL_STATUS" -ne 0 ]; then
    log_error "One or more filtering steps failed. Aborting before RSEM reference preparation."
    rm -rf "$tmp_decomp_dir"
    exit "$OVERALL_STATUS"
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
    "${outDir}/genome"

OVERALL_STATUS=$?

# Clean up temporary decompressed files
rm -rf "$tmp_decomp_dir"

if [ "$OVERALL_STATUS" -ne 0 ]; then
    log_sep
    log_error "rsem-prepare-reference failed. See errors above."
    log_error "Pipeline Terminated with Errors."
    exit $OVERALL_STATUS
fi

log_sep
log_info "Outputs generated in $outDir"
log_success "RSEM reference preparation completed successfully."
log_success "Pipeline Terminated Successfully."