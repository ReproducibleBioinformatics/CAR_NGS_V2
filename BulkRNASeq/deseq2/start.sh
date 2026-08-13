#!/bin/bash
# ==============================================================================
# Script: start.sh
# Description: Single-file DESeq2 Execution Wrapper for Differential Expression
# Container: docker4seq-deseq2-v2
# ==============================================================================
DOCKER_NAME="docker4seq-deseq2-v2"

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
    echo -e "  $0 <results> <matrix_path> <matrix_sep> <metadata> <metadata_sep> <log2fc> <fdr> <ref_covar> <target_covar> <threads> <quiet>"
    echo ""
    echo -e "${YELLOW}Arguments (all mandatory):${NC}"
    echo -e "  ${CYAN}results${NC}        Output directory for differential expression results"
    echo -e "  ${CYAN}matrix_path${NC}    Path to the count matrix file (.csv, .tsv, .txt)"
    echo -e "  ${CYAN}matrix_sep${NC}     Field separator used in count matrix (e.g., ',' ';' or 'tab')"
    echo -e "  ${CYAN}metadata${NC}       Path to the sample metadata table"
    echo -e "  ${CYAN}metadata_sep${NC}   Field separator used in metadata file (e.g., ',' ';' or 'tab')"
    echo -e "  ${CYAN}log2fc${NC}         Absolute Log2 Fold Change threshold for filtering (e.g., 1.0)"
    echo -e "  ${CYAN}fdr${NC}            FDR / Adjusted p-value significance threshold (e.g., 0.05)"
    echo -e "  ${CYAN}ref_covar${NC}      Baseline/Control group level in metadata (e.g., 'control')"
    echo -e "  ${CYAN}target_covar${NC}   Treatment/Target group level in metadata (e.g., 'treated')"
    echo -e "  ${CYAN}threads${NC}        Number of parallel threads (positive integer)"
    echo -e "  ${CYAN}quiet${NC}          Suppress processing log messages: 'true' or 'false'"
    log_sep "-" "$YELLOW"
}

# ------- Argument Checking ------- #
# All arguments are mandatory: always use -ne <N> for an exact count check.
if [ "$#" -ne 11 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_usage
    exit 1
fi

# ------- Positional Arguments Assignment ------- #
results="${1}"
matrix_path="${2}"
matrix_sep="${3}"
metadata="${4}"
metadata_sep="${5}"
log2fc="${6}"
fdr="${7}"
ref_covar="${8}"
target_covar="${9}"
threads="${10}"
quiet="${11}"

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
echo -e "  ${CYAN}Matrix File     :${NC} ${YELLOW}${matrix_path}${NC}"
echo -e "  ${CYAN}Matrix Sep      :${NC} '${YELLOW}${matrix_sep}${NC}'"
echo -e "  ${CYAN}Metadata        :${NC} ${YELLOW}${metadata}${NC}"
echo -e "  ${CYAN}Metadata Sep    :${NC} '${YELLOW}${metadata_sep}${NC}'"
echo -e "  ${CYAN}Log2FC Threshold:${NC} ${YELLOW}${log2fc}${NC}"
echo -e "  ${CYAN}FDR Threshold   :${NC} ${YELLOW}${fdr}${NC}"
echo -e "  ${CYAN}Reference Level :${NC} ${YELLOW}${ref_covar}${NC}"
echo -e "  ${CYAN}Target Level    :${NC} ${YELLOW}${target_covar}${NC}"
echo -e "  ${CYAN}Threads         :${NC} ${YELLOW}${threads}${NC}"
echo -e "  ${CYAN}Quiet Mode      :${NC} ${YELLOW}${quiet}${NC}"
log_sep "=" "$CYAN"
log_info "Initializing DESeq2 Pipeline Wrapper"

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
# Always call the destination directory "Results directory" in BOTH checks
# below - never mix "Results directory" and "Output directory" for the same
# variable within the same script.
if [ ! -d "$results" ]; then
    log_error "Results directory '$results' does not exist."
    exit 1
fi
if [ -n "$(find "$results" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    log_error "Results directory '$results' is not empty. Terminating pipeline to prevent overwriting existing data."
    exit 1
fi

# ------- Check Input Matrix File ------- #
if [ ! -f "$matrix_path" ]; then
    log_error "Input count matrix file '$matrix_path' does not exist."
    exit 1
fi

# ------- Check Metadata File ------- #
# Every step driven by a metadata file must validate its presence using this
# exact wording and variable name ("metadata"), before touching its content.
if [ ! -f "$metadata" ]; then
    log_error "Sample metadata file '$metadata' does not exist."
    exit 1
fi

# ------- Validate and Normalize Metadata Separator ------- #
# Shared pattern across every metadata-driven step: normalizes "metadata_sep"
# in place, accepting ',', ';', 'tab', '\t' (case-insensitive). Copy this
# function verbatim into any script that reads a metadata file - do not
# reimplement it differently between scripts.
parse_separator_inplace() {
    local -n sep_ref="${1}"
    local sep_clean

    sep_clean=$(echo "$sep_ref" | xargs | tr '[:upper:]' '[:lower:]')

    case "$sep_clean" in
        "tab"|"\t"|"\\t")
            sep_ref=$'\t'
            return 0
            ;;
        ","|";")
            sep_ref="$sep_clean"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}
if ! parse_separator_inplace metadata_sep; then
    log_error "Invalid metadata separator provided: '$metadata_sep'. Allowed values: ',', ';', '\t', 'tab'."
    exit 1
fi

# ------- Validate and Normalize Matrix Separator ------- #
# Same shared function reused for the count matrix separator - do not
# reimplement it, just apply it to a different variable.
if ! parse_separator_inplace matrix_sep; then
    log_error "Invalid separator '$matrix_sep'. Use ',' or ';' for CSV, '\t' or 'tab' for TSV."
    exit 1
fi

# ------- Validate Log2FC Threshold ------- #
if ! [[ "$log2fc" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    log_error "The log2fc parameter must be a non-negative number (provided: '$log2fc')"
    exit 1
fi

# ------- Validate FDR Threshold ------- #
if ! [[ "$fdr" =~ ^[0-9]+(\.[0-9]+)?$ ]] || ! awk -v v="$fdr" 'BEGIN { exit !(v >= 0 && v <= 1) }'; then
    log_error "The fdr parameter must be a number between 0 and 1 (provided: '$fdr')"
    exit 1
fi

# ------- Validate Reference/Target Covariate Levels ------- #
if [ "$ref_covar" == "$target_covar" ]; then
    log_error "The ref_covar and target_covar parameters must be different (both provided: '$ref_covar')"
    exit 1
fi

# ------- Locate Core R Script (One-time lookup) ------- #
core_script_path=""
if [ -f "/usr/local/bin/core.R" ]; then
    core_script_path="/usr/local/bin/core.R"
elif [ -f "./core.R" ]; then
    core_script_path="./core.R"
else
    log_error "Core DESeq2 script (core.R) not found in /usr/local/bin/ or current working directory."
    exit 1
fi

# ==============================================================================
# EXIT CODE SCHEME
# exit 1 -> usage / argument / input / metadata validation errors (everything above this line)
# exit 2 -> failure of the FIRST external tool or script invoked below (core.R / Rscript)
# ==============================================================================

# ------- Core Processing Step: DESeq2 Execution via core.R ------- #
file_name=$(basename "$matrix_path")
log_sep "-" "$YELLOW"
log_step "Processing matrix [${file_name}] -> Target Output: [${results}]"

Rscript "$core_script_path" \
    "$results" \
    "$matrix_path" \
    "$matrix_sep" \
    "$metadata" \
    "$metadata_sep" \
    "$log2fc" \
    "$fdr" \
    "$ref_covar" \
    "$target_covar" \
    "$threads" \
    "$quiet"

r_status=$?
if [ $r_status -ne 0 ]; then
    log_error "core.R failed for '${file_name}' with exit code $r_status."
    exit 2
fi
log_success "core.R executed successfully for '${file_name}' (Threads used: $threads)."

# ------- Final Output Check ------- #
# TODO: verify expected outputs exist in $results before declaring success.

log_sep "=" "$CYAN"
log_success "Pipeline Terminated Successfully."
