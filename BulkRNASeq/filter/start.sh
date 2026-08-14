#!/bin/bash
DOCKER_NAME="docker4seq-filter-v2"

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
    echo -e "  $0 <de_full> <raw_counts> <norm_counts> <results> <log2fc> <padj> <threads> <quiet>"
    echo ""
    echo -e "${YELLOW}Arguments (all mandatory):${NC}"
    echo -e "  ${CYAN}de_full${NC}      Path to the full differential expression analysis file"
    echo -e "  ${CYAN}raw_counts${NC}   Path to the raw counts matrix file"
    echo -e "  ${CYAN}norm_counts${NC}  Path to the normalized counts matrix file"
    echo -e "  ${CYAN}results${NC}      Output directory for filtered results"
    echo -e "  ${CYAN}log2fc${NC}       Log2 fold change threshold (e.g., 1)"
    echo -e "  ${CYAN}padj${NC}         Adjusted p-value / FDR threshold (between 0 and 1, e.g., 0.1)"
    echo -e "  ${CYAN}threads${NC}      Number of parallel threads for data.table I/O (positive integer)"
    echo -e "  ${CYAN}quiet${NC}        Suppress processing log messages: 'true' or 'false'"
    log_sep "-" "$YELLOW"
}

# ------- Argument Checking ------- #
# All arguments are mandatory: use -ne <N> for an exact count check.
if [ "$#" -ne 8 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_usage
    exit 1
fi

# ------- Positional Arguments Assignment ------- #
de_full="${1}"
raw_counts="${2}"
norm_counts="${3}"
results="${4}"
log2fc="${5}"
padj="${6}"
threads="${7}"
quiet="${8}"

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
echo -e "  ${CYAN}Docker Container :${NC} ${GREEN}${DOCKER_NAME}${NC}"
echo -e "  ${CYAN}DE Full File     :${NC} ${YELLOW}${de_full}${NC}"
echo -e "  ${CYAN}Raw Counts File  :${NC} ${YELLOW}${raw_counts}${NC}"
echo -e "  ${CYAN}Norm Counts File :${NC} ${YELLOW}${norm_counts}${NC}"
echo -e "  ${CYAN}Results Dir      :${NC} ${YELLOW}${results}${NC}"
echo -e "  ${CYAN}Log2FC Threshold :${NC} ${YELLOW}${log2fc}${NC}"
echo -e "  ${CYAN}Padj Threshold   :${NC} ${YELLOW}${padj}${NC}"
echo -e "  ${CYAN}Threads          :${NC} ${YELLOW}${threads}${NC}"
echo -e "  ${CYAN}Quiet Mode       :${NC} ${YELLOW}${quiet}${NC}"
log_sep "=" "$CYAN"
log_info "Initializing DE Results Filter Pipeline Wrapper"

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
if [ ! -f "$de_full" ]; then
    log_error "DE_full file '$de_full' does not exist."
    exit 1
fi

if [ ! -f "$raw_counts" ]; then
    log_error "Raw counts file '$raw_counts' does not exist."
    exit 1
fi

if [ ! -f "$norm_counts" ]; then
    log_error "Normalized counts file '$norm_counts' does not exist."
    exit 1
fi

# ------- Validate log2fc Parameter ------- #
if ! [[ "$log2fc" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    log_error "The log2fc parameter must be numeric (provided: '$log2fc')."
    exit 1
fi

if [ "$(echo "$log2fc" | awk '{if ($1 < 0) print 1; else print 0}')" -eq 1 ]; then
    log_error "The log2fc parameter must be non-negative, since it represents an absolute fold-change threshold (provided: '$log2fc')."
    exit 1
fi

# ------- Validate padj Parameter ------- #
if ! [[ "$padj" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    log_error "The padj parameter must be numeric (provided: '$padj')."
    exit 1
fi

if [ "$(echo "$padj" | awk '{if ($1 <= 0 || $1 > 1) print 1; else print 0}')" -eq 1 ]; then
    log_error "The padj parameter must be between 0 (exclusive) and 1 (inclusive) (provided: '$padj')."
    exit 1
fi

log_success "All input parameters validated successfully."
log_sep "-" "$YELLOW"

# ==============================================================================
# EXIT CODE SCHEME
# exit 1 -> usage / argument / input / parameter validation errors (everything above this line)
# exit 2 -> failure of filter_de_results.R (Rscript, first and only external tool invoked below)
# ==============================================================================

# ------- Core Processing Step: Run Filtering Script (filter_de_results.R) ------- #
log_step "Running Filtering Script (filter_de_results.R)..."
Rscript /usr/local/bin/filter_de_results.R "$de_full" "$raw_counts" "$norm_counts" "$results" "$log2fc" "$padj" "$threads" "$quiet"
r_status=$?
log_sep

if [ $r_status -eq 0 ]; then
    log_success "filter_de_results.R executed successfully (Threads used: $threads)."
else
    log_error "filter_de_results.R failed with exit code $r_status."
    exit 2
fi

# ------- Final Output Check ------- #
log_success "Pipeline Terminated Successfully."