#!/bin/bash
DOCKER_NAME="docker4seq-pca-v2"

NC='\033[0m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'
log_info() { [ "$QUIET" == "true" ] && return; echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} INFO]    ${1}${NC}"; }
log_step() { [ "$QUIET" == "true" ] && return; echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} PROCESS] ${1}${NC}"; }
log_warn() { [ "$QUIET" == "true" ] && return; echo -e "${ORANGE}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} WARNING] ${1}${NC}"; }
log_success() { [ "$QUIET" == "true" ] && return; echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} SUCCESS] ${1}${NC}"; }
log_error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} ERROR]   ${1}${NC}"; }
log_sep() { [ "$QUIET" == "true" ] && return; echo -e "${2:-$CYAN}$(printf '%0.s'"${1:-=}" {1..100})${NC}"; }
# ------- Helper to validate boolean flags ------- #
validate_boolean() {
    local val_lower
    val_lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "$val_lower" in
        true|1|yes)  echo "TRUE" ;;
        false|0|no) echo "FALSE" ;;
        *)          echo "INVALID" ;;
    esac
}
# ------- show usage ------- #
show_usage() {
    log_sep "-" "$YELLOW"
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  $0 <results> <matrix_path> <matrix_sep> <metadata> <metadata_sep> <pca_type> <log_transform> <remove_zero_var> <blind> <threads> <quiet>"
    echo ""
    echo -e "${YELLOW}Arguments (all mandatory):${NC}"
    echo -e "  ${CYAN}results${NC}         Output directory where PCA results will be stored"
    echo -e "  ${CYAN}matrix_path${NC}     Path to single count matrix file (.csv, .tsv, .txt)"
    echo -e "  ${CYAN}matrix_sep${NC}      Field separator for the count matrix file (e.g., ',', ';', 'tab')"
    echo -e "  ${CYAN}metadata${NC}        Path to metadata file"
    echo -e "  ${CYAN}metadata_sep${NC}    Field separator for the metadata file (e.g., ',', ';', 'tab')"
    echo -e "  ${CYAN}pca_type${NC}        Type of PCA analysis: 'standard', 'deseq', or 'deseqNormalized'"
    echo -e "  ${CYAN}log_transform${NC}   Apply log2 transformation: 'true' or 'false'"
    echo -e "  ${CYAN}remove_zero_var${NC} Filter zero variance genes: 'true' or 'false'"
    echo -e "  ${CYAN}blind${NC}           Whether to ignore the experimental design during transformation: 'true' or 'false'"
    echo -e "  ${CYAN}threads${NC}         Number of parallel threads (positive integer)"
    echo -e "  ${CYAN}quiet${NC}           Suppress processing log messages: 'true' or 'false'"
    log_sep "-" "$YELLOW"
}
parse_separator_inplace() {
    local -n sep_ref="${1}"
    local sep_clean=$(echo "$sep_ref" | xargs | tr '[:upper:]' '[:lower:]')
    case "$sep_clean" in
        "tab"|"\t"|$'\t')
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
# ------- Argument Checking All arguments are mandatory ------- #
if [ "$#" -ne 11 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then show_usage; exit 1; fi
# ------- Positional Arguments Assignment ------- #
results="${1}"
matrix_path="${2}"
matrix_sep="${3}"
metadata="${4}"
metadata_sep="${5}"
pca_type=$(echo "${6}" | tr '[:upper:]' '[:lower:]')
raw_log_transform="${7}"
raw_remove_zero_var="${8}"
raw_blind="${9}"
threads="${10}"
quiet="${11}"
# ------- Validate Quiet Parameter ------- #
if [ "$quiet" != "true" ] && [ "$quiet" != "false" ]; then log_warn "Invalid quiet parameter '$quiet', defaulting to 'false'"; quiet="false"; fi; QUIET="$quiet"
# ------- Validate and Normalize Boolean Parameters ------- #
log_transform=$(validate_boolean "$raw_log_transform")
if [ "$log_transform" == "INVALID" ]; then log_error "Invalid log_transform value '$raw_log_transform'. Expected 'true' or 'false'."; exit 1; fi
remove_zero_var=$(validate_boolean "$raw_remove_zero_var")
if [ "$remove_zero_var" == "INVALID" ]; then log_error "Invalid remove_zero_var value '$raw_remove_zero_var'. Expected 'true' or 'false'."; exit 1; fi
blind=$(validate_boolean "$raw_blind")
if [ "$blind" == "INVALID" ]; then log_error "Invalid blind value '$raw_blind'. Expected 'true' or 'false'."; exit 1; fi
# ------- Print Pipeline Execution Context ------- #
if [ "$QUIET" == "false" ]; then 
    log_sep "=" "$CYAN"
    log_info "Pipeline Execution Context:"
    echo -e "  ${CYAN}Docker Container:${NC} ${GREEN}${DOCKER_NAME}${NC}"
    echo -e "  ${CYAN}Results Dir     :${NC} ${YELLOW}${results}${NC}"
    echo -e "  ${CYAN}Matrix File     :${NC} ${YELLOW}${matrix_path}${NC}"
    echo -e "  ${CYAN}Matrix Sep      :${NC} '${YELLOW}${matrix_sep}${NC}'"
    echo -e "  ${CYAN}Metadata        :${NC} ${YELLOW}${metadata}${NC}"
    echo -e "  ${CYAN}Metadata Sep    :${NC} '${YELLOW}${metadata_sep}${NC}'"
    echo -e "  ${CYAN}PCA Type        :${NC} ${YELLOW}${pca_type}${NC}"
    echo -e "  ${CYAN}Log Transform   :${NC} ${YELLOW}${log_transform}${NC}"
    echo -e "  ${CYAN}Remove Zero Var :${NC} ${YELLOW}${remove_zero_var}${NC}"
    echo -e "  ${CYAN}Blind           :${NC} ${YELLOW}${blind}${NC}"
    echo -e "  ${CYAN}Threads         :${NC} ${YELLOW}${threads}${NC}"
    echo -e "  ${CYAN}Quiet Mode      :${NC} ${YELLOW}${quiet}${NC}"
    log_sep "=" "$CYAN"
    log_info "Initializing PCA Pipeline Wrapper"
fi
# ------- Validate an optimize Threads Parameter and allocation ------- #
max_cores=$(nproc)
if ! [[ "$threads" =~ ^[0-9]+$ ]] || [ "$threads" -le 0 ]; then log_warn "Invalid threads parameter '$threads' (must be a positive integer). Defaulting to 1."; threads=1; fi
if [ "$threads" -gt "$max_cores" ]; then log_warn "Requested threads ($threads) exceed available CPU cores ($max_cores). Capping allocation to $max_cores."; threads=$max_cores; fi
export OMP_NUM_THREADS=$threads
# ------- Check Results Directory ------- #
if [ ! -d "$results" ]; then log_error "Results directory '$results' does not exist."; exit 1; fi
if [ -n "$(find "$results" -mindepth 1 -print -quit 2>/dev/null)" ]; then log_error "Results directory '$results' is not empty. Terminating pipeline to prevent overwriting existing data."; exit 1; fi
# ------- Check Metadata File ------- #
if [ ! -f "$metadata" ]; then log_error "Sample metadata file '$metadata' does not exist."; exit 1; fi
# ------- Validate and Normalize Metadata Separator ------- #
if ! parse_separator_inplace metadata_sep; then log_error "Invalid metadata separator provided: '$metadata_sep'. Allowed values: ',', ';', '\t', 'tab'."; exit 1; fi
# ------- Validate and Normalize Matrix Separator ------- #
if ! parse_separator_inplace matrix_sep; then log_error "Invalid matrix separator provided: '$matrix_sep'. Allowed values: ',', ';', '\t', 'tab'."; exit 1; fi
# ------- Validate Metadata Content via R Script ------- #
if ! Rscript /usr/local/bin/check_samplemetadata.R "$metadata" "$metadata_sep" "" "$quiet"; then log_error "Validation of metadata file failed. Terminating pipeline."; exit 1; fi
# ------- Check Input Matrix File ------- #
if [ ! -f "$matrix_path" ]; then log_error "Matrix file '$matrix_path' does not exist or is not a regular file."; exit 1; fi
if [ ! -s "$matrix_path" ]; then log_error "Matrix file '$matrix_path' is empty."; exit 1; fi
# ------- Validate PCA Type ------- #
case "$pca_type" in
    standard|deseq|deseqnormalized) ;;
    *)
        log_error "Unsupported pca_type '$pca_type'. Allowed values: 'standard', 'deseq', 'deseqNormalized'."
        exit 1
        ;;
esac
# ------- Run PCA Analysis ------- #
file_name=$(basename "$matrix_path")
log_step "Processing file [${file_name}] -> Saving output directly to [${results}]"
if [ "$pca_type" == "standard" ]; then
    log_step "Running Standard PCA via /usr/local/bin/plot_pca.R..."
    Rscript /usr/local/bin/plot_pca.R "$matrix_path" "$matrix_sep" "$metadata" "$metadata_sep" "$results" "$log_transform" "$remove_zero_var" "$threads" "$quiet"
    R_STATUS=$?
else
    log_step "Running DESeq2 PCA (mode: $pca_type) via /usr/local/bin/run_deseq2.R..."
    Rscript /usr/local/bin/run_deseq2.R "$matrix_path" "$matrix_sep" "$metadata" "$metadata_sep" "$results" "$pca_type" "$blind" "$threads" "$quiet"
    R_STATUS=$?
fi
if [ $R_STATUS -ne 0 ]; then log_error "PCA execution failed for ${file_name} with exit status $R_STATUS."; exit 2; fi
log_success "PCA execution for ${file_name} completed successfully."