#!/bin/bash
DOCKER_NAME="docker4seq-qc_report-v2"

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
    echo -e "  $0 <input_dir> <results> <metadata> <metadata_sep> <threads> <quiet>"
    echo ""
    echo -e "${YELLOW}Arguments (all mandatory):${NC}"
    echo -e "  ${CYAN}input_dir${NC}      Base directory containing raw or structured FASTQ files"
    echo -e "  ${CYAN}results${NC}        Output directory for FastQC and MultiQC results"
    echo -e "  ${CYAN}metadata${NC}       Path to the metadata file containing sample names and folders"
    echo -e "  ${CYAN}metadata_sep${NC}   Field separator used in metadata (e.g., ';', ',', 'tab')"
    echo -e "  ${CYAN}threads${NC}        Number of parallel threads (positive integer)"
    echo -e "  ${CYAN}quiet${NC}          Suppress processing log messages: 'true' or 'false'"
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
if [ "$#" -ne 6 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then show_usage; exit 1; fi
# ------- Positional Arguments Assignment ------- #
input_dir="${1}"
results="${2}"
metadata="${3}"
metadata_sep="${4}"
threads="${5}"
quiet="${6}"
# ------- Validate Quiet Parameter ------- #
if [ "$quiet" != "true" ] && [ "$quiet" != "false" ]; then log_warn "Invalid quiet parameter '$quiet', defaulting to 'false'"; quiet="false"; fi; QUIET="$quiet"
# ------- Print Pipeline Execution Context ------- #
if [ "$QUIET" == "false" ] then 
    log_sep "=" "$CYAN"
    log_info "Pipeline Execution Context:"
    echo -e "  ${CYAN}Docker Container:${NC} ${GREEN}${DOCKER_NAME}${NC}"
    echo -e "  ${CYAN}Input Dir       :${NC} ${YELLOW}${input_dir}${NC}"
    echo -e "  ${CYAN}Results Dir     :${NC} ${YELLOW}${results}${NC}"
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
# ------- Check Metadata File ------- #
if [ ! -f "$metadata" ]; then log_error "Sample metadata file '$metadata' does not exist."; exit 1; fi
# ------- Validate and Normalize Metadata Separator ------- #
if ! parse_separator_inplace metadata_sep; then log_error "Invalid metadata separator provided: '$metadata_sep'. Allowed values: ',', ';', '\t', 'tab'."; exit 1; fi
# ------- Validate Metadata Content via R Script ------- #
if ! Rscript /usr/local/bin/check_samplemetadata.R "$metadata" "$metadata_sep" "" "$quiet"; then log_error "Validation of metadata file failed. Terminating pipeline."; exit 1; fi
# ------- Parse Metadata Header ------- #
idx_name=-1
idx_folder=-1
header=$(head -n 1 "$metadata" | tr -d '\r')
IFS="$metadata_sep" read -ra cols <<< "$header"
for i in "${!cols[@]}"; do
    col_trimmed=$(echo "${cols[$i]}" | xargs)
    if [ "$col_trimmed" == "SampleName" ]; then idx_name=$((i + 1))
    elif [ "$col_trimmed" == "SampleFolder" ]; then idx_folder=$((i + 1)); fi
done
# ------- Loop through metadata rows (skipping header) ------- #
tmp_results="${results}/_tmp_fastqc"
mkdir -p "$tmp_results"
fastqc_quiet_flag=""
if [ "$QUIET" == "true" ]; then fastqc_quiet_flag="-q"; fi
while IFS="$metadata_sep" read -ra row || [ -n "${row[0]}" ]; do
    if [ ${#row[@]} -eq 0 ]; then continue; fi
    raw_name="${row[$((idx_name - 1))]}"
    sample_name=$(echo "$raw_name" | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//' | xargs)
    sample_folder=""
    if [ "$idx_folder" -ne -1 ] && [ ${#row[@]} -ge $idx_folder ]; then raw_folder="${row[$((idx_folder - 1))]}"; sample_folder=$(echo "$raw_folder" | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//' | xargs); fi
    if [ -z "$sample_name" ]; then continue; fi
    if [ -n "$sample_folder" ]; then target_file="${input_dir}/${sample_folder}/${sample_name}"; else target_file="${input_dir}/${sample_name}"; fi
    if [ ! -f "$target_file" ]; then log_warn "File not found: '$target_file'. Skipping FastQC execution."; continue; fi
    log_info "Running FastQC on: $target_file"
    if fastqc "$target_file" --threads "$threads" $fastqc_quiet_flag -o "$tmp_results"; then
        prefix=""
        if [ -n "$sample_folder" ]; then prefix="$(echo "$sample_folder" | tr '/' '_')_"; fi
        base_name=$(basename "$sample_name")
        clean_base="${base_name%.gz}"
        clean_base="${clean_base%.fastq}"
        clean_base="${clean_base%.fq}"
        html_out="${tmp_results}/${clean_base}_fastqc.html"
        zip_out="${tmp_results}/${clean_base}_fastqc.zip"
        dest_html="${results}/${prefix}${clean_base}_fastqc.html"
        dest_zip="${results}/${prefix}${clean_base}_fastqc.zip"
        if [ -f "$html_out" ]; then mv "$html_out" "$dest_html"; fi
        if [ -f "$zip_out" ]; then mv "$zip_out" "$dest_zip"; fi
        log_success "Generated outputs for '${sample_name}' with prefix '${prefix}'"
    else
        log_error "FastQC processing failed for: $target_file"
    fi
done < <(tail -n +2 "$metadata" | tr -d '\r')
rm -rf "$tmp_results"
if [ -z "$(find "$results" -maxdepth 1 -name "*_fastqc.zip" 2>/dev/null)" ]; then log_error "No FastQC outputs found in output directory. Skipping MultiQC."; exit 2; fi
# ------- Running MultiQC ------- #
log_info "Running MultiQC..."
multiqc_quiet_flag=""
if [ "$QUIET" == "true" ]; then multiqc_quiet_flag="--quiet"; fi
if multiqc "$results" -o "$results" --cl-config "max_subprocs: $threads" $multiqc_quiet_flag; then log_success "MultiQC completed successfully."; else log_error "MultiQC failed."; exit 3; fi
log_success "Pipeline Terminated Successfully."