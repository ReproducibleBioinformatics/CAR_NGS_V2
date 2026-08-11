#!/bin/bash
# ==============================================================================
# Pipeline wrapper script for RSEM-STAR Index execution.
# All parameters, including folders, are hardcoded constants: no dynamic
# output-folder search and no argument validation are performed.
# ==============================================================================
SCRIPT_NAME="test-rsemstarindex"

# ------- Hardcoded Constants ------- #
workdir="workdir"
results="results/"
genome_fa="../testdata/Genome/Drosophila_melanogaster.BDGP6.46.dna.toplevel.fa"
gtf_file="../testdata/Genome/Drosophila_melanogaster.BDGP6.46.112.gtf"
mito_pattern="mito"
chrom_pattern='^(2L|2R|3L|3R|4|X|Y)$'
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
echo -e "  ${CYAN}Genome FASTA    :${NC} ${YELLOW}${genome_fa}${NC}"
echo -e "  ${CYAN}GTF File        :${NC} ${YELLOW}${gtf_file}${NC}"
echo -e "  ${CYAN}Mito Pattern    :${NC} ${YELLOW}${mito_pattern}${NC}"
echo -e "  ${CYAN}Chrom Pattern   :${NC} '${YELLOW}${chrom_pattern}${NC}'"
echo -e "  ${CYAN}Threads         :${NC} ${YELLOW}${threads}${NC}"
echo -e "  ${CYAN}Quiet Mode      :${NC} ${YELLOW}${quiet}${NC}"
log_sep "=" "$CYAN"
log_info "Initializing RSEM-STAR Index Pipeline Wrapper"

# ==============================================================================
# EXIT CODE SCHEME
# exit 1 -> failure of python3 rsemstarindex.py execution
# ==============================================================================

# ------- Core Processing Step: RSEM-STAR Index Execution ------- #
log_step "Executing RSEM-STAR Index pipeline via Python wrapper..."
log_sep

python3 rsemstarindex.py "$workdir" "$results" "$genome_fa" "$gtf_file" "$mito_pattern" "$chrom_pattern" "$threads" "$quiet"
cmd_exit_code=$?

if [ $cmd_exit_code -ne 0 ]; then
    log_error "Python execution of rsemstarindex.py failed with exit code $cmd_exit_code."
    exit 1
fi

log_sep
log_success "Pipeline Terminated Successfully."