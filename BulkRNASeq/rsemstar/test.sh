#!/bin/bash
# ==============================================================================
# Pipeline wrapper script for RSEM-STAR execution.
# Configured with hardcoded constant parameters and dynamic output folder search.
# ==============================================================================
SCRIPT_NAME="test-rsemstar"

# ------- Hardcoded Constants ------- #
workdir="workdir"
results="results"
metadata_sep=","
strandness="none"
save_bam="true"
seq_type="pe"
threads=5
quiet="true"

NC='\033[0m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'
log_info() { [ "$QUIET" == "true" ] && return; echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} INFO]    ${1}${NC}"; }
log_step() { [ "$QUIET" == "true" ] && return; echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} PROCESS] ${1}${NC}"; }
log_warn() { [ "$QUIET" == "true" ] && return; echo -e "${ORANGE}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} WARNING] ${1}${NC}"; }
log_success() { [ "$QUIET" == "true" ] && return; echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} SUCCESS] ${1}${NC}"; }
log_error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} ERROR]   ${1}${NC}"; }
log_sep() { [ "$QUIET" == "true" ] && return; echo -e "${2:-$CYAN}$(printf '%0.s'${1:-=} {1..100})${NC}"; }

QUIET="$quiet"

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

# ------- Resolve Dynamic Paths (skewer and rsemstarindex) ------- #
input_dir=$(get_latest_output_dir "../skewer/results")
genome_dir=$(get_latest_output_dir "../rsemstarindex/results")

# ------- Print Pipeline Execution Context ------- #
log_sep "=" "$CYAN"
log_info "Pipeline Execution Context:"
echo -e "  ${CYAN}Script Name     :${NC} ${GREEN}${SCRIPT_NAME}${NC}"
echo -e "  ${CYAN}Work Dir        :${NC} ${YELLOW}${workdir}${NC}"
echo -e "  ${CYAN}Input Dir       :${NC} ${YELLOW}${input_dir}${NC}"
echo -e "  ${CYAN}Genome Dir      :${NC} ${YELLOW}${genome_dir}${NC}"
echo -e "  ${CYAN}Results Dir     :${NC} ${YELLOW}${results}${NC}"
echo -e "  ${CYAN}Metadata Sep    :${NC} '${YELLOW}${metadata_sep}${NC}'"
echo -e "  ${CYAN}Strandness      :${NC} ${YELLOW}${strandness}${NC}"
echo -e "  ${CYAN}Save BAM        :${NC} ${YELLOW}${save_bam}${NC}"
echo -e "  ${CYAN}Seq Type        :${NC} ${YELLOW}${seq_type}${NC}"
echo -e "  ${CYAN}Threads         :${NC} ${YELLOW}${threads}${NC}"
echo -e "  ${CYAN}Quiet Mode      :${NC} ${YELLOW}${quiet}${NC}"
log_sep "=" "$CYAN"
log_info "Initializing RSEM-STAR Pipeline Wrapper"

# ------- Validate Input and Genome Directories ------- #
log_step "Validating parameters and environment..."
if [ -z "$input_dir" ] || [ ! -d "$input_dir" ]; then
    log_error "Could not find a valid skewer output directory under '../skewer/results'."
    exit 1
fi

if [ -z "$genome_dir" ] || [ ! -d "$genome_dir" ]; then
    log_error "Could not find a valid rsemstarindex output directory under '../rsemstarindex/results'."
    exit 1
fi

# ------- Validate Metadata File ------- #
metadata="${input_dir}/sampleMetaData_skewer.csv"
if [ ! -f "$metadata" ]; then
    log_error "Sample metadata file '$metadata' does not exist."
    exit 1
fi

# ------- Optimize Threads Allocation ------- #
max_cores=$(nproc)
if [ "$threads" -gt "$max_cores" ]; then
    log_warn "Requested threads ($threads) exceed available CPU cores ($max_cores). Capping allocation to $max_cores."
    threads=$max_cores
fi

# ------- Check Results Directory ------- #
if [ ! -d "$results" ]; then
    mkdir -p "$results"
    log_info "Created Results directory '$results'."
fi

# ==============================================================================
# EXIT CODE SCHEME
# exit 1 -> input / metadata validation errors
# exit 2 -> failure of python3 rsemstar.py execution
# ==============================================================================

# ------- Core Processing Step: RSEM-STAR Execution ------- #
log_step "Executing RSEM-STAR pipeline via Python wrapper..."
log_sep

python3 rsemstar.py "$workdir" "$input_dir" "$genome_dir" "$results" "$metadata" "$metadata_sep" "$strandness" "$save_bam" "$seq_type" "$threads" "$quiet"
cmd_exit_code=$?

if [ $cmd_exit_code -ne 0 ]; then
    log_error "Python execution of rsemstar.py failed with exit code $cmd_exit_code."
    exit 2
fi

log_sep
log_success "Pipeline Terminated Successfully."