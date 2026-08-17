#!/bin/bash
DOCKER_NAME="docker4seq-rsemstarindex-v2"

NC='\033[0m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'
log_info() { [ "$QUIET" == "true" ] && return; echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} INFO]    ${1}${NC}"; }
log_step() { [ "$QUIET" == "true" ] && return; echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} PROCESS] ${1}${NC}"; }
log_warn() { [ "$QUIET" == "true" ] && return; echo -e "${ORANGE}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} WARNING] ${1}${NC}"; }
log_success() { [ "$QUIET" == "true" ] && return; echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} SUCCESS] ${1}${NC}"; }
log_error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} ERROR]   ${1}${NC}"; }
log_sep() { [ "$QUIET" == "true" ] && return; echo -e "${2:-$CYAN}$(printf '%0.s'"${1:-=}" {1..100})${NC}"; }
# ------- show usage ------- #
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
# ------- Argument Checking All arguments are mandatory ------- #
if [ "$#" -ne 7 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then show_usage; exit 1; fi
# ------- Positional Arguments Assignment ------- #
results="${1}"
fastafile="${2}"
gtffile="${3}"
filter="${4}"
chrom_pattern="${5}"
threads="${6}"
quiet="${7}"
# ------- Validate Quiet Parameter ------- #
if [ "$quiet" != "true" ] && [ "$quiet" != "false" ]; then log_warn "Invalid quiet parameter '$quiet', defaulting to 'false'"; quiet="false"; fi; QUIET="$quiet"
# ------- Print Pipeline Execution Context ------- #
if [ "$QUIET" == "false" ]; then 
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
fi
# ------- Validate an optimize Threads Parameter and allocation ------- #
max_cores=$(nproc)
if ! [[ "$threads" =~ ^[0-9]+$ ]] || [ "$threads" -le 0 ]; then log_warn "Invalid threads parameter '$threads' (must be a positive integer). Defaulting to 1."; threads=1; fi
if [ "$threads" -gt "$max_cores" ]; then log_warn "Requested threads ($threads) exceed available CPU cores ($max_cores). Capping allocation to $max_cores."; threads=$max_cores; fi
export OMP_NUM_THREADS=$threads
# ------- Check Results Directory ------- #
if [ ! -d "$results" ]; then log_error "Results directory '$results' does not exist."; exit 1; fi
if [ -n "$(find "$results" -mindepth 1 -print -quit 2>/dev/null)" ]; then log_error "Results directory '$results' is not empty. Terminating pipeline to prevent overwriting existing data."; exit 1; fi
# ------- Check Input Files ------- #
if [ -z "$fastafile" ] || [ ! -f "$fastafile" ]; then log_error "FASTA file parameter is empty or the file '$fastafile' does not exist."; exit 1; fi
if [ -z "$gtffile" ] || [ ! -f "$gtffile" ]; then log_error "GTF file parameter is empty or the file '$gtffile' does not exist."; exit 1; fi
# ------- Validate Filter Parameter ------- #
case "$filter" in none|all|mito|chrom) ;; *) log_error "Unsupported filter '$filter'. Allowed values: 'none', 'all', 'mito', 'chrom'."; exit 1 ;; esac
# ------- Step 1: Decompress Input Files Upfront ------- #
tmp_decomp_dir="${results}/_tmp_decomp"
mkdir -p "$tmp_decomp_dir"
target_gtf="${tmp_decomp_dir}/annotation.gtf"
target_fasta="${tmp_decomp_dir}/genome.fa"
if [[ "$gtffile" == *.gz ]]; then log_info "Decompressing GTF file..."; gunzip -c "$gtffile" > "$target_gtf"; else cp "$gtffile" "$target_gtf"; fi
if [[ "$fastafile" == *.gz ]]; then log_info "Decompressing FASTA file...";  gunzip -c "$fastafile" > "$target_fasta"; else cp "$fastafile" "$target_fasta"; fi
# ------- Step 2: Apply Filters on Decompressed Files ------- #
overall_status=0
if [ "$filter" == "none" ]; then log_info "filter=none: skipping all filtering steps."; fi
if [ "$filter" == "all" ] || [ "$filter" == "mito" ]; then run_remove_mitochondrion; status_r=$?; fi
if [ "$overall_status" -eq 0 ] && { [ "$filter" == "all" ] || [ "$filter" == "chrom" ]; }; then run_filter_chromosomes; status_r=$?; fi
if [ "$overall_status" -ne 0 ] && [ "$overall_status" -ne 3 ]; then log_error "One or more filtering steps failed. Aborting before RSEM reference preparation."; rm -rf "$tmp_decomp_dir"; exit "$overall_status"; fi
# ------- Step 3: Run RSEM Prepare Reference ------- #
log_step "Building RSEM/STAR genome index..."
"rsem-prepare-reference" -p "$threads" --star --star-path /usr/local/bin/ --gtf "$target_gtf" "$target_fasta" "${results}/genome"
overall_status=$?
# ------- Clean Up Temporary Directory ------- #
rm -rf "$tmp_decomp_dir"
# ------- Final Output Check ------- #
if [ "$overall_status" -ne 0 ]; then log_error "rsem-prepare-reference failed. See errors above."; exit $overall_status; fi
log_success "RSEM reference preparation completed successfully. Outputs generated in $results"