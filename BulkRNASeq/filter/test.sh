#!/bin/bash
# ==============================================================================
# Pipeline wrapper script for Filter execution.
# All parameters, including folders, are hardcoded constants: no dynamic
# output-folder search and no argument validation are performed.
# ==============================================================================
SCRIPT_NAME="test-filter"

# ------- Hardcoded Constants ------- #
workdir="workdir"
results="results/"
de_full="../testdata/DESeq2/DEfull_batch.txt"
raw_counts="../testdata/DESeq2/experiment_counts.txt"
norm_counts="../testdata/DESeq2/log2normalized_counts.txt"
log2fc="1.0"
padj="0.05"
threads=8
quiet="false"
mkdir -p "$workdir" "$results"

NC='\033[0m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'
log_info() { [ "$QUIET" == "true" ] && return; echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} INFO]    ${1}${NC}"; }
log_step() { [ "$QUIET" == "true" ] && return; echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} PROCESS] ${1}${NC}"; }
log_warn() { [ "$QUIET" == "true" ] && return; echo -e "${ORANGE}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} WARNING] ${1}${NC}"; }
log_success() { [ "$QUIET" == "true" ] && return; echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} SUCCESS] ${1}${NC}"; }
log_error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} ERROR]   ${1}${NC}"; }
log_sep() { [ "$QUIET" == "true" ] && return; echo -e "${2:-$CYAN}$(printf '%0.s'${1:-=} {1..100})${NC}"; }

QUIET="$quiet"

# ------- Print Pipeline Execution Context ------- #
log_sep "=" "$CYAN"
log_info "Pipeline Execution Context:"
echo -e "  ${CYAN}Script Name     :${NC} ${GREEN}${SCRIPT_NAME}${NC}"
echo -e "  ${CYAN}Work Dir        :${NC} ${YELLOW}${workdir}${NC}"
echo -e "  ${CYAN}Results Dir     :${NC} ${YELLOW}${results}${NC}"
echo -e "  ${CYAN}DE Full File    :${NC} ${YELLOW}${de_full}${NC}"
echo -e "  ${CYAN}Raw Counts      :${NC} ${YELLOW}${raw_counts}${NC}"
echo -e "  ${CYAN}Norm Counts     :${NC} ${YELLOW}${norm_counts}${NC}"
echo -e "  ${CYAN}Log2FC Thresh   :${NC} ${YELLOW}${log2fc}${NC}"
echo -e "  ${CYAN}Padj Thresh     :${NC} ${YELLOW}${padj}${NC}"
echo -e "  ${CYAN}Threads         :${NC} ${YELLOW}${threads}${NC}"
echo -e "  ${CYAN}Quiet Mode      :${NC} ${YELLOW}${quiet}${NC}"
log_sep "=" "$CYAN"
log_info "Initializing Filter Pipeline Wrapper"

# ==============================================================================
# EXIT CODE SCHEME
# exit 1 -> failure of python3 filter.py execution
# ==============================================================================

# ------- Core Processing Step: Filter Execution ------- #
log_step "Executing Filter pipeline via Python wrapper..."
log_sep

python3 filter.py "$workdir" "$de_full" "$raw_counts" "$norm_counts" "$results" "$log2fc" "$padj" "$threads" "$quiet"
cmd_exit_code=$?

if [ $cmd_exit_code -ne 0 ]; then
    log_error "Python execution of filter.py failed with exit code $cmd_exit_code."
    exit 1
fi

log_sep
log_success "Pipeline Terminated Successfully."