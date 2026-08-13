#!/bin/bash
# ==============================================================================
# Pipeline wrapper script for DESeq2 execution.
# All parameters, including folders, are hardcoded constants: no dynamic
# output-folder search and no argument validation are performed.
# ==============================================================================
SCRIPT_NAME="test-deseq2"

# ------- Hardcoded Constants ------- #
workdir="workdir"
results="results/"
log2fc=1.0
fdr=0.05
ref_covar="control"
target_covar="treated"
metadata_sep=","
matrix_sep="tab"
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

# ==============================================================================
# EXIT CODE SCHEME 
# exit 1 -> failure of python3 deseq2.py execution
# ==============================================================================

# ------- Core Processing Step: DESeq2 Execution ------- #
log_step "Executing DESeq2 pipeline via Python wrapper..."
log_sep

# ------- Function to Find Highest Output Directory ------- #
get_latest_output_dir() {
    local base_dir="${1}"
    local max_num=-1
    local latest_dir=""

    if [ ! -d "$base_dir" ]; then
        echo ""
        return
    fi

    for dir in "${base_dir}"/output*; do
        if [ -d "$dir" ]; then
            folder_name=$(basename "$dir")
            num="${folder_name#output}"
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -gt "$max_num" ]; then
                max_num=$num
                latest_dir="$dir"
            fi
        fi
    done

    echo "$latest_dir"
}

input_dir=$(get_latest_output_dir "../annotation/results")
metadata="${input_dir}/sampleMetaData_annotation.csv"
matrix_path="${input_dir}/experiment_counts.txt"

# ------- Print Pipeline Execution Context ------- #
log_sep "=" "$CYAN"
log_info "Pipeline Execution Context:"
echo -e "  ${CYAN}Script Name     :${NC} ${GREEN}${SCRIPT_NAME}${NC}"
echo -e "  ${CYAN}Work Dir        :${NC} ${YELLOW}${workdir}${NC}"
echo -e "  ${CYAN}Results Dir     :${NC} ${YELLOW}${results}${NC}"
echo -e "  ${CYAN}Metadata File   :${NC} ${YELLOW}${metadata}${NC}"
echo -e "  ${CYAN}Matrix Path     :${NC} ${YELLOW}${matrix_path}${NC}"
echo -e "  ${CYAN}Matrix Sep      :${NC} ${YELLOW}${matrix_sep}${NC}"
echo -e "  ${CYAN}Metadata Sep    :${NC} ${YELLOW}${metadata_sep}${NC}"
echo -e "  ${CYAN}Log2FC Threshold:${NC} ${YELLOW}${log2fc}${NC}"
echo -e "  ${CYAN}FDR Threshold   :${NC} ${YELLOW}${fdr}${NC}"
echo -e "  ${CYAN}Reference Level :${NC} ${YELLOW}${ref_covar}${NC}"
echo -e "  ${CYAN}Target Level    :${NC} ${YELLOW}${target_covar}${NC}"
echo -e "  ${CYAN}Threads         :${NC} ${YELLOW}${threads}${NC}"
echo -e "  ${CYAN}Quiet Mode      :${NC} ${YELLOW}${quiet}${NC}"
log_sep "=" "$CYAN"
log_info "Initializing Pipeline Wrapper"


python3 deseq2.py "$workdir" "$results" "$matrix_path" "$matrix_sep" "$metadata" "$metadata_sep" "$log2fc" "$fdr" "$ref_covar" "$target_covar" "$threads" "$quiet"
cmd_exit_code=$?

if [ $cmd_exit_code -ne 0 ]; then
    log_error "Python execution of deseq2.py failed with exit code $cmd_exit_code."
    exit 1
fi

log_sep
log_success "Pipeline Terminated Successfully."