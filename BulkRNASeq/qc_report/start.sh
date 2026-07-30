#!/bin/bash
DOCKER_NAME="docker4seq-qc_report-v2"

NC='\033[0m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'
log_info() { echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} INFO]    ${1}${NC}"; }
log_step() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} PROCESS] ${1}${NC}"; }
log_warn() { echo -e "${ORANGE}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} WARNING] ${1}${NC}"; }
log_success() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} SUCCESS] ${1}${NC}"; }
log_error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} ERROR]   ${1}${NC}"; }
log_sep() { echo -e "${2:-$CYAN}$(printf '%0.s'${1:-=} {1..100})${NC}"; }

show_usage() {
    log_sep "-" "$YELLOW"
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  $0 <data_fastq> <results> <samplemetadata> <separator> [threads]"
    echo ""
    echo -e "${YELLOW}Arguments:${NC}"
    echo -e "  ${CYAN}data_fastq${NC}      Base directory containing raw or structured FASTQ files"
    echo -e "  ${CYAN}results${NC}         Output directory for FastQC and MultiQC results"
    echo -e "  ${CYAN}samplemetadata${NC}  Path to the metadata file containing sample names and folders"
    echo -e "  ${CYAN}separator${NC}       Field separator used in samplemetadata (e.g., ';' or ',')"
    echo -e "  ${CYAN}threads${NC}         Number of parallel threads (Optional, default: 1)"
    log_sep "-" "$YELLOW"
}

if [ "$#" -lt 4 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_usage
    exit 1
fi

data_fastq="${1}"
results="${2}"
samplemetadata="${3}"
separator="${4}"
threads="${5:-1}"

log_sep "=" "$CYAN"
log_info "Pipeline Execution Context:"
echo -e "  ${CYAN}Docker Container:${NC} ${GREEN}${DOCKER_NAME}${NC}"
echo -e "  ${CYAN}Input FASTQ Dir :${NC} ${YELLOW}${data_fastq}${NC}"
echo -e "  ${CYAN}Results Dir     :${NC} ${YELLOW}${results}${NC}"
echo -e "  ${CYAN}Sample Metadata :${NC} ${YELLOW}${samplemetadata}${NC}"
echo -e "  ${CYAN}Metadata Sep    :${NC} '${YELLOW}${separator}${NC}'"
echo -e "  ${CYAN}Threads Allocated:${NC}${YELLOW}${threads}${NC}"
log_sep "=" "$CYAN"
log_info "Initializing FastQC and MultiQC Pipeline Wrapper"

# ------- Validate threads parameter ------- #
log_step "Validating parameters and environment..."
if ! [[ "$threads" =~ ^[0-9]+$ ]] || [ "$threads" -le 0 ]; then
    log_error "The threads parameter must be a positive integer (provided: '$threads')"
    exit 1
fi

max_cores=$(nproc)
if [ "$threads" -gt "$max_cores" ]; then
    log_warn "Requested threads ($threads) exceed available CPU cores ($max_cores). Capping allocation to $max_cores."
    threads=$max_cores
fi

# ------- Check input directories and metadata file ------- #
if [ ! -d "$data_fastq" ]; then
    log_error "Data directory '$data_fastq' does not exist."
    exit 1
fi

if [ ! -d "$results" ]; then
    log_error "Results directory '$results' does not exist."
    exit 1
fi

if [ -n "$(find "$results" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    log_error "Output directory '$results' is not empty. Terminating pipeline to prevent overwriting existing data."
    exit 1
fi

if [ ! -f "$samplemetadata" ]; then
    log_error "Sample metadata file '$samplemetadata' does not exist."
    exit 1
fi

# ------- Validate Metadata via R script ------- #
log_step "Validating sample metadata content via R script..."
if ! Rscript /usr/local/bin/check_samplemetadata.R "$samplemetadata" "$separator"; then
    log_error "Validation of metadata file failed. Terminating pipeline."
    exit 1
fi

# ------- Parse Metadata Header ------- #
header=$(head -n 1 "$samplemetadata" | tr -d '\r')

idx_name=-1
idx_folder=-1

IFS="$separator" read -ra cols <<< "$header"
for i in "${!cols[@]}"; do
    col_trimmed=$(echo "${cols[$i]}" | xargs)
    if [ "$col_trimmed" == "SampleName" ]; then
        idx_name=$((i + 1))
    elif [ "$col_trimmed" == "SampleFolder" ]; then
        idx_folder=$((i + 1))
    fi
done

if [ "$idx_name" -eq -1 ]; then
    log_error "Column 'SampleName' not found in metadata file."
    exit 1
fi

log_info "Metadata parsing configured successfully (SampleName col: $idx_name, SampleFolder col: $idx_folder)."

# ------- Processing Samples with FastQC ------- #
tmp_results="${results}/_tmp_fastqc"
mkdir -p "$tmp_results"

log_step "Processing samples with FastQC..."
log_sep

sample_count=0
success_count=0

# Loop through metadata rows (skipping header)
tail -n +2 "$samplemetadata" | tr -d '\r' | while IFS="$separator" read -ra row; do
    [ ${#row[@]} -eq 0 ] && continue

    sample_name=$(echo "${row[$((idx_name - 1))]}" | xargs)
    sample_folder=""
    if [ "$idx_folder" -ne -1 ] && [ ${#row[@]} -ge $idx_folder ]; then
        sample_folder=$(echo "${row[$((idx_folder - 1))]}" | xargs)
    fi

    [ -z "$sample_name" ] && continue

    # Resolve target input path
    if [ -n "$sample_folder" ]; then
        target_file="${data_fastq}/${sample_folder}/${sample_name}"
    else
        target_file="${data_fastq}/${sample_name}"
    fi

    if [ ! -f "$target_file" ]; then
        log_warn "File not found: '$target_file'. Skipping FastQC execution."
        continue
    fi

    log_info "Running FastQC on: $target_file"
    if fastqc "$target_file" --threads "$threads" -q -o "$tmp_results"; then
        # Determine prefix based on samplefolder
        prefix=""
        if [ -n "$sample_folder" ]; then
            prefix="$(echo "$sample_folder" | tr '/' '_')_"
        fi

        # Base file name without extensions
        base_name=$(basename "$sample_name")
        clean_base="${base_name%.gz}"
        clean_base="${clean_base%.fastq}"
        clean_base="${clean_base%.fq}"

        # FastQC default output filenames
        html_out="${tmp_results}/${clean_base}_fastqc.html"
        zip_out="${tmp_results}/${clean_base}_fastqc.zip"

        # Destination paths in output root
        dest_html="${results}/${prefix}${clean_base}_fastqc.html"
        dest_zip="${results}/${prefix}${clean_base}_fastqc.zip"

        if [ -f "$html_out" ]; then mv "$html_out" "$dest_html"; fi
        if [ -f "$zip_out" ]; then mv "$zip_out" "$dest_zip"; fi

        log_success "Generated outputs for '${sample_name}' with prefix '${prefix}'"
    else
        log_error "FastQC processing failed for: $target_file"
    fi
done

# Clean up temporary directory
rm -rf "$tmp_results"

# Check if any FastQC outputs were produced
if [ -z "$(find "$results" -maxdepth 1 -name "*_fastqc.zip" 2>/dev/null)" ]; then
    log_error "No FastQC outputs found in output directory. Skipping MultiQC."
    exit 1
fi

# ------- Running MultiQC ------- #
log_step "Running MultiQC..."
log_sep
if multiqc "$results" -o "$results" --cl-config "max_subprocs: $threads"; then
    log_success "MultiQC completed successfully."
else
    log_error "MultiQC failed."
    exit 1
fi

log_sep
log_success "Pipeline Terminated Successfully."