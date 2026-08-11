#!/bin/bash
# ==============================================================================
# Pipeline wrapper script for Skewer execution.
# All parameters, including folders, are hardcoded constants: no dynamic
# output-folder search and no argument validation are performed.
# ==============================================================================
SCRIPT_NAME="test-skewer"

# ------- Hardcoded Constants ------- #
workdir="workdir"
input_dir="raw_data/"
results="results/"
adapter1="AGATCGGAAGAGCACACGTCTGAACTCCAGTCA"
adapter2="AGATCGGAAGAGCGTCGTGTAGGGAAAGAGTGT"
seq_type="pe"
metadata="raw_data/sampleMetaData.csv"
metadata_sep=","
threads=10
quiet="false"

NC='\033[0m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'
log_info() { [ "$QUIET" == "true" ] && return; echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} INFO]    ${1}${NC}"; }
log_step() { [ "$QUIET" == "true" ] && return; echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} PROCESS] ${1}${NC}"; }
log_warn() { [ "$QUIET" == "true" ] && return; echo -e "${ORANGE}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} WARNING] ${1}${NC}"; }
log_success() { [ "$QUIET" == "true" ] && return; echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} SUCCESS] ${1}${NC}"; }
log_error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} ERROR]   ${1}${NC}"; }
log_sep() { [ "$QUIET" == "true" ] && return; echo -e "${2:-$CYAN}$(printf '%0.s'${1:-=} {1..100})${NC}"; }

QUIET="$quiet"
mkdir -p "$workdir" "$results"

# ------- Print Pipeline Execution Context ------- #
log_sep "=" "$CYAN"
log_info "Pipeline Execution Context:"
echo -e "  ${CYAN}Script Name     :${NC} ${GREEN}${SCRIPT_NAME}${NC}"
echo -e "  ${CYAN}Work Dir        :${NC} ${YELLOW}${workdir}${NC}"
echo -e "  ${CYAN}Input Dir       :${NC} ${YELLOW}${input_dir}${NC}"
echo -e "  ${CYAN}Results Dir     :${NC} ${YELLOW}${results}${NC}"
echo -e "  ${CYAN}Adapter 1       :${NC} ${YELLOW}${adapter1}${NC}"
echo -e "  ${CYAN}Adapter 2       :${NC} ${YELLOW}${adapter2}${NC}"
echo -e "  ${CYAN}Seq Type        :${NC} ${YELLOW}${seq_type}${NC}"
echo -e "  ${CYAN}Metadata        :${NC} ${YELLOW}${metadata}${NC}"
echo -e "  ${CYAN}Metadata Sep    :${NC} '${YELLOW}${metadata_sep}${NC}'"
echo -e "  ${CYAN}Threads         :${NC} ${YELLOW}${threads}${NC}"
echo -e "  ${CYAN}Quiet Mode      :${NC} ${YELLOW}${quiet}${NC}"
log_sep "=" "$CYAN"
log_info "Initializing Skewer Pipeline Wrapper"

# ==============================================================================
# EXIT CODE SCHEME
# exit 1 -> failure of python3 skewer.py execution
# ==============================================================================

# ------- Core Processing Step: Skewer Execution ------- #
log_step "Executing Skewer pipeline via Python wrapper..."
log_sep

python3 skewer.py "$workdir" "$input_dir" "$results" "$adapter1" "$adapter2" "$seq_type" "$metadata" "$metadata_sep" "$threads" "$quiet"
cmd_exit_code=$?

if [ $cmd_exit_code -ne 0 ]; then
    log_error "Python execution of skewer.py failed with exit code $cmd_exit_code."
    exit 1
fi

log_sep
log_success "Pipeline Terminated Successfully."