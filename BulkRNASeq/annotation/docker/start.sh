#!/bin/bash
DOCKER_NAME="docker4seq-annotation-v2"

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
    echo -e "  $0 <input_dir> <results> <annotation_file> <gene_biotype> <metadata> <metadata_sep> <threads> <quiet>"
    echo ""
    echo -e "${YELLOW}Arguments (all mandatory):${NC}"
    echo -e "  ${CYAN}input_dir${NC}       Directory containing RSEM results files (*.genes.results)"
    echo -e "  ${CYAN}results${NC}         Output directory for aggregated expression tables"
    echo -e "  ${CYAN}annotation_file${NC} Path to reference annotation GTF/GFF3 file"
    echo -e "  ${CYAN}gene_biotype${NC}    Filtering Ensembl biotype or 'all' to skip filtering"
    echo -e "  ${CYAN}metadata${NC}        Path to the metadata file containing sample names and folders"
    echo -e "  ${CYAN}metadata_sep${NC}    Field separator used in metadata (e.g., ';', ',', 'tab')"
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
if [ "$#" -ne 9 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then show_usage; exit 1; fi
# ------- Positional Arguments Assignment ------- #
input_dir="${1}"
results="${2}"
annotation_file="${3}"
gene_biotype="${4}"
metadata="${5}"
metadata_sep="${6}"
threads="${7}"
quiet="${8}"
# ------- Validate Quiet Parameter ------- #
if [ "$quiet" != "true" ] && [ "$quiet" != "false" ]; then log_warn "Invalid quiet parameter '$quiet', defaulting to 'false'"; quiet="false"; fi; QUIET="$quiet"
# ------- Print Pipeline Execution Context ------- #
if [ "$QUIET" == "false" ]; then 
    log_sep "=" "$CYAN"
    log_info "Pipeline Execution Context:"
    echo -e "  ${CYAN}Docker Container:${NC} ${GREEN}${DOCKER_NAME}${NC}"
    echo -e "  ${CYAN}Input Dir       :${NC} ${YELLOW}${input_dir}${NC}"
    echo -e "  ${CYAN}Results Dir     :${NC} ${YELLOW}${results}${NC}"
    echo -e "  ${CYAN}Annotation File :${NC} ${YELLOW}${annotation_file}${NC}"
    echo -e "  ${CYAN}Gene Biotype    :${NC} ${YELLOW}${gene_biotype}${NC}"
    echo -e "  ${CYAN}Metadata        :${NC} ${YELLOW}${metadata}${NC}"
    echo -e "  ${CYAN}Metadata Sep    :${NC} '${YELLOW}${metadata_sep}${NC}'"
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
# ------- Check Input Directory ------- #
if [ ! -d "$input_dir" ]; then log_error "Input directory '$input_dir' does not exist."; exit 1; fi
# ------- Check Annotation File ------- #
if [ ! -f "$annotation_file" ]; then log_error "Annotation file '$annotation_file' does not exist."; exit 1; fi
# ------- Check Metadata File ------- #
if [ ! -f "$metadata" ]; then log_error "Sample metadata file '$metadata' does not exist."; exit 1; fi
# ------- Validate and Normalize Metadata Separator ------- #
if ! parse_separator_inplace metadata_sep; then log_error "Invalid metadata separator provided: '$metadata_sep'. Allowed values: ',', ';', '\t', 'tab'."; exit 1; fi
# ------- Validate Metadata Content via R Script ------- #
if ! Rscript /usr/local/bin/check_samplemetadata.R "$metadata" "$metadata_sep" "" "$quiet"; then log_error "Validation of metadata file failed. Terminating pipeline."; exit 1; fi
# ------- Validate Gene Biotype Parameter ------- #
if [ -z "$gene_biotype" ]; then log_error "Missing required parameter: gene_biotype."; exit 1; fi
# ------- Check for Sample Files in Input Directory ------- #
genes_count=$(find "$input_dir" -maxdepth 1 -type f -name "*.genes.results" | wc -l)
if [ "$genes_count" -eq 0 ]; then log_error "No *.genes.results files found in $input_dir."; exit 1; fi
log_info "Found $genes_count genes.results file(s) in the input directory."
# ------- Step 1: Extract Gene Mapping from Annotation File ------- #
gene_map_cache="${input_dir}/gene_annotation_map.tsv"
Rscript /usr/local/bin/extract_gene_mapping.R "$annotation_file" "$gene_biotype" "$gene_map_cache" "$threads" "$quiet"
if [ $? -ne 0 ] || [ ! -f "$gene_map_cache" ]; then log_error "Failed to build gene annotation mapping from '$annotation_file'."; exit 2; fi
# ------- Step 2: Aggregate and Annotate Expression Matrices ------- #
Rscript /usr/local/bin/generate_expression_tables.R "$metadata" "$metadata_sep" "$input_dir" "$results" "$gene_biotype" "$gene_map_cache" "$threads" "$quiet"
if [ $? -ne 0 ]; then log_error "Failed to aggregate expression matrices."; exit 3; fi
log_success "Expression matrices successfully built and saved to: $results"