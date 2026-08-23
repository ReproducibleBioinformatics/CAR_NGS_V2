#!/bin/bash
DOCKER_NAME="docker4seq-rsemstar-v2"
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
    echo -e "  $0 <inputDir> <genomeDir> <outDir> <metadata> <metadata_sep> <strandness> <save_bam> <seq_type> <threads> <quiet>"
    echo ""
    echo -e "${YELLOW}Arguments (all mandatory):${NC}"
    echo -e "  ${CYAN}inputDir${NC}      Base directory containing raw or structured FASTQ files"
    echo -e "  ${CYAN}genomeDir${NC}     Directory containing STAR and RSEM reference index files"
    echo -e "  ${CYAN}outDir${NC}        Output directory for final quantification results"
    echo -e "  ${CYAN}metadata${NC}      Path to the metadata file containing sample names and numbers"
    echo -e "  ${CYAN}metadata_sep${NC}  Field separator used in metadata (e.g., ';', ',', 'tab')"
    echo -e "  ${CYAN}strandness${NC}    Strand specificity: 'none', 'forward', or 'reverse'"
    echo -e "  ${CYAN}save_bam${NC}      Save aligned BAM files: 'true' or 'false'"
    echo -e "  ${CYAN}seq_type${NC}      Sequencing type: 'se' (Single-End) or 'pe' (Paired-End)"
    echo -e "  ${CYAN}threads${NC}       Number of parallel threads (positive integer)"
    echo -e "  ${CYAN}quiet${NC}         Suppress processing log messages: 'true' or 'false'"
    log_sep "-" "$YELLOW"
}
parse_separator_inplace() {
    local -n sep_ref="${1}"
    local sep_clean
    sep_clean=$(echo "$sep_ref" | xargs | tr '[:upper:]' '[:lower:]')
    if [ "$sep_clean" = "tab" ] || [ "$sep_clean" = '\t' ] || [ "$sep_clean" = $'\t' ]; then sep_ref='\t';  return 0;
    elif [ "$sep_clean" = "," ] || [ "$sep_clean" = ";" ]; then sep_ref="$sep_clean"; return 0;
    else return 1; fi
}
# ------- Argument Checking All arguments are mandatory ------- #
if [ "$#" -ne 10 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then show_usage; exit 1; fi
# ------- Positional Arguments Assignment ------- #
input_dir="${1}"
genome_dir="${2}"
results="${3}"
metadata="${4}"
metadata_sep="${5}"
strandness="${6}"
save_bam="${7}"
seq_type="${8,,}"
threads="${9}"
quiet="${10}"
# ------- Validate Quiet Parameter ------- #
if [ "$quiet" != "true" ] && [ "$quiet" != "false" ]; then log_warn "Invalid quiet parameter '$quiet', defaulting to 'false'"; quiet="false"; fi; QUIET="$quiet"
# ------- Print Pipeline Execution Context ------- #
if [ "$QUIET" == "false" ]; then 
    log_sep "=" "$CYAN"
    log_info "Pipeline Execution Context:"
    echo -e "  ${CYAN}Docker Container:${NC} ${GREEN}${DOCKER_NAME}${NC}"
    echo -e "  ${CYAN}Input Dir       :${NC} ${YELLOW}${input_dir}${NC}"
    echo -e "  ${CYAN}Genome Dir      :${NC} ${YELLOW}${genome_dir}${NC}"
    echo -e "  ${CYAN}Results Dir     :${NC} ${YELLOW}${results}${NC}"
    echo -e "  ${CYAN}Metadata        :${NC} ${YELLOW}${metadata}${NC}"
    echo -e "  ${CYAN}Metadata Sep    :${NC} '${YELLOW}${metadata_sep}${NC}'"
    echo -e "  ${CYAN}Strandness      :${NC} ${YELLOW}${strandness}${NC}"
    echo -e "  ${CYAN}Save BAM        :${NC} ${YELLOW}${save_bam}${NC}"
    echo -e "  ${CYAN}Seq Type        :${NC} ${YELLOW}${seq_type}${NC}"
    echo -e "  ${CYAN}Threads         :${NC} ${YELLOW}${threads}${NC}"
    echo -e "  ${CYAN}Quiet Mode      :${NC} ${YELLOW}${quiet}${NC}"
    log_sep "=" "$CYAN"
    log_info "Initializing RSEM/STAR Pipeline Wrapper"
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
if [ -z "$(find "$input_dir" -maxdepth 1 -type f 2>/dev/null)" ]; then log_error "Input directory '$input_dir' contains no files."; exit 1; fi
# ------- Check Metadata File ------- #
if [ ! -f "$metadata" ]; then log_error "Sample metadata file '$metadata' does not exist."; exit 1; fi
# ------- Validate and Normalize Metadata Separator ------- #
if ! parse_separator_inplace metadata_sep; then log_error "Invalid metadata separator provided: '$metadata_sep'. Allowed values: ',', ';', '\t', 'tab'."; exit 1; fi
# ------- Validate Metadata Content via R Script ------- #
if ! Rscript /usr/local/bin/check_samplemetadata.R "$metadata" "$metadata_sep" "$seq_type" "$quiet"; then log_error "Validation of metadata file failed. Terminating pipeline."; exit 1; fi
# ------- Check Genome Directory (module-specific) ------- #
if [ ! -d "$genome_dir" ]; then log_error "Genome directory '$genome_dir' does not exist."; exit 1; fi
if [ ! -f "$genome_dir/genomeParameters.txt" ]; then log_error "Genome directory '$genome_dir' does not contain STAR index files (missing genomeParameters.txt)."; exit 1; fi
if [ -z "$(find "$genome_dir" -maxdepth 1 -type f -name "*.seq" 2>/dev/null)" ]; then log_error "Genome directory '$genome_dir' does not contain RSEM reference index files."; exit 1; fi
# ------- Validate Enum Parameters (module-specific) ------- #
if [[ "$strandness" != "none" && "$strandness" != "forward" && "$strandness" != "reverse" ]]; then log_error "Invalid strandness '$strandness'. Must be 'none', 'forward' or 'reverse'."; exit 1; fi
if [ "$seq_type" != "se" ] && [ "$seq_type" != "pe" ]; then log_error "Invalid sequence type '$seq_type'. Must be 'se' or 'pe'."; exit 1; fi
if [[ "$save_bam" != "true" && "$save_bam" != "false" ]]; then log_warn "save_bam '$save_bam' not recognized, defaulting to 'false'."; save_bam="false"; fi
# ------- Load Metadata into RAM (Associative Arrays) ------- #
declare -A col_map
declare -A meta_rows
header=$(head -n 1 "$metadata" | tr -d '\r')
IFS="$metadata_sep" read -ra cols <<< "$header"
for i in "${!cols[@]}"; do
    col_clean=$(echo "${cols[$i]}" | xargs | tr '[:upper:]' '[:lower:]')
    col_map["$col_clean"]=$i
done
row_idx=0
while IFS="$metadata_sep" read -ra row; do
    [ ${#row[@]} -eq 0 ] && continue
    row_str=$(IFS="$metadata_sep"; echo "${row[*]}")
    meta_rows["$row_idx"]="$row_str"
    ((row_idx++))
done < <(tail -n +2 "$metadata" | tr -d '\r')
get_field() {
    local key="$1"
    local col_name="$2"
    local c_idx="${col_map[${col_name,,}]}"
    if [ -n "$c_idx" ]; then
        IFS="$metadata_sep" read -ra fields <<< "${meta_rows[$key]}"
        echo "${fields[$c_idx]}" | xargs
    fi
}
update_field() {
    local key="$1"
    local col_name="$2"
    local new_val="$3"
    local c_idx="${col_map[${col_name,,}]}"
    if [ -n "$c_idx" ]; then
        IFS="$metadata_sep" read -ra fields <<< "${meta_rows[$key]}"
        fields[$c_idx]="$new_val"
        meta_rows["$key"]=$(IFS="$metadata_sep"; echo "${fields[*]}")
    fi
}
strip_fastq_ext() {
    local s="$1"
    s="${s%.fastq.gz}"
    s="${s%.fastq}"
    s="${s%.fq.gz}"
    s="${s%.fq}"
    printf '%s' "$s"
}
collect_outputs() {
    local prefix="$1"
    mv "$results/${prefix}.genes.results" "$results/${prefix}.genes.results" 2>/dev/null
    mv "$results/${prefix}.isoforms.results" "$results/${prefix}.isoforms.results" 2>/dev/null
    local star_log
    star_log=$(find "$results" -name "${prefix}*Log.final.out" -print -quit)
    if [ -n "$star_log" ]; then
        mv "$star_log" "$results/${prefix}.Log.final.out"
    else
        log_warn "Log.final.out not found for '${prefix}', skipping."
    fi
    if [ "$save_bam" == "true" ]; then
        local genome_bam transcript_bam
        genome_bam=$(find "$results" -name "${prefix}.genome.bam" -print -quit)
        transcript_bam=$(find "$results" -name "${prefix}.transcript.bam" -print -quit)
        [ -n "$genome_bam" ] && cp "$genome_bam" "$results/${prefix}.Aligned.out.bam" 2>/dev/null
        [ -n "$transcript_bam" ] && cp "$transcript_bam" "$results/${prefix}.Aligned.toTranscriptome.out.bam" 2>/dev/null
    fi
    find "$results" -maxdepth 1 -name "${prefix}*" -exec rm -rf {} + 2>/dev/null
}
# ------- Sort Metadata Keys by SampleNumber ------- #
sorted_keys=()
while IFS= read -r key; do
    sorted_keys+=("$key")
done < <(
    for key in "${!meta_rows[@]}"; do
        snum=$(get_field "$key" "samplenumber")
        echo -e "${snum}\t${key}"
    done | sort -k1,1n | cut -f2
)
# ------- Processing Samples with RSEM-STAR ------- #
tmp_results="${results}/_tmp_rsem"
mkdir -p "$tmp_results"
updated_metadata="${tmp_results}/updated_metadata.csv"
echo "$header" > "$updated_metadata"
log_step "Processing samples with RSEM-STAR ($seq_type mode, strandness: $strandness)..."
i=0
total_samples=${#sorted_keys[@]}
overall_status=0
while [ $i -lt $total_samples ]; do
    key1="${sorted_keys[$i]}"
    snum1=$(get_field "$key1" "samplenumber")
    sname1=$(get_field "$key1" "samplename")
    sfolder1=$(get_field "$key1" "samplefolder")
    if [ -z "$sname1" ]; then
        ((i++))
        continue
    fi
    if [ -n "$sfolder1" ]; then
        target1="${input_dir}/${sfolder1}/${sname1}"
        prefix1="$(echo "$sfolder1" | tr '/' '_')_"
    else
        target1="${input_dir}/${sname1}"
        prefix1=""
    fi
    if [ "$seq_type" == "se" ]; then
        if [ ! -f "$target1" ]; then
            log_warn "File not found: '$target1'. Skipping."
            overall_status=1
            ((i++))
            continue
        fi
        log_info "Running RSEM [SE]: $target1"
        base1=$(basename "$sname1")
        clean_label=$(strip_fastq_ext "$base1")
        out_prefix="${prefix1}${clean_label}"
        local_gz_opt=""
        if [[ "$sname1" =~ \.gz$ ]]; then local_gz_opt="--star-gzipped-read-file"; fi
        if "/usr/local/bin/RSEM-1.3.3/rsem-calculate-expression" \
            --output-genome-bam \
            --keep-intermediate-files \
            -p "$threads" \
            --strandedness "$strandness" \
            --star \
            $local_gz_opt \
            --star-path "/usr/local/bin/" \
            "$target1" \
            "$genome_dir/genome" \
            "$results/${out_prefix}"; then
            collect_outputs "$out_prefix"
            log_success "Generated SE quantification for: '${sname1}' (Prefix: ${out_prefix})"
            new_sname1="${out_prefix}.genes.results"
            update_field "$key1" "samplename" "$new_sname1"
            if [ -n "${col_map["samplefolder"]}" ]; then update_field "$key1" "samplefolder" ""; fi
            echo "${meta_rows[$key1]}" >> "$updated_metadata"
        else
            log_error "RSEM processing failed for: $target1"
            overall_status=1
        fi
        ((i++))
    elif [ "$seq_type" == "pe" ]; then
        next_idx=$((i + 1))
        if [ $next_idx -ge $total_samples ]; then
            log_warn "Unpaired sample at end of metadata (SampleNumber: $snum1, File: $sname1). Skipping."
            overall_status=1
            ((i++))
            continue
        fi
        key2="${sorted_keys[$next_idx]}"
        snum2=$(get_field "$key2" "samplenumber")
        sname2=$(get_field "$key2" "samplename")
        sfolder2=$(get_field "$key2" "samplefolder")
        if [ "$snum1" != "$snum2" ]; then log_warn "Mismatch in SampleNumber for PE pair: '$snum1' vs '$snum2' (File: $sname1). Skipping."; overall_status=1; ((i++)); continue; fi
        if [ -n "$sfolder2" ]; then target2="${input_dir}/${sfolder2}/${sname2}";
        else target2="${input_dir}/${sname2}"; fi
        if [ ! -f "$target1" ] || [ ! -f "$target2" ]; then log_warn "Missing FASTQ file(s) for pair ($sname1 / $sname2). Skipping."; overall_status=1; i=$((i + 2)); continue; fi
        log_info "Running RSEM [PE]: '$sname1' and '$sname2' (SampleNumber: $snum1)"
        out_prefix="sample_${snum1}"
        local_gz_opt=""
        if [[ "$sname1" =~ \.gz$ ]]; then local_gz_opt="--star-gzipped-read-file"; fi
        if "/usr/local/bin/RSEM-1.3.3/rsem-calculate-expression" \
            --output-genome-bam \
            --keep-intermediate-files \
            -p "$threads" \
            --strandedness "$strandness" \
            --paired-end \
            --star \
            $local_gz_opt \
            --star-path "/usr/local/bin/" \
            "$target1" "$target2" \
            "$genome_dir/genome" \
            "$results/${out_prefix}"; then
            collect_outputs "$out_prefix"
            log_success "Generated PE outputs for group SampleNumber '${snum1}' (${out_prefix})"
            new_sname1="${out_prefix}.genes.results"
            update_field "$key1" "samplename" "$new_sname1"
            if [ -n "${col_map["samplefolder"]}" ]; then update_field "$key1" "samplefolder" ""; fi
            echo "${meta_rows[$key1]}" >> "$updated_metadata"
        else
            log_error "RSEM processing failed for PE pair: $sname1 / $sname2"
            overall_status=1
        fi
        i=$((i + 2))
    fi
done
# ------- Save Updated Metadata File ------- #
metadata_filename=$(basename "$metadata")
base_meta_name="${metadata_filename%.*}"
meta_ext="${metadata_filename##*.}"
base_meta_name="${base_meta_name%_skewer}"
if [ "$base_meta_name" == "$meta_ext" ]; then
    out_metadata_filename="${base_meta_name}_rsemstar"
else
    out_metadata_filename="${base_meta_name}_rsemstar.${meta_ext}"
fi
if [ -f "$updated_metadata" ]; then
    mv "$updated_metadata" "${results}/${out_metadata_filename}"
    log_info "Saved updated metadata to '${results}/${out_metadata_filename}'"
fi
chmod 777 "$results" -R 2>/dev/null
rm -rf "$tmp_results"
# ------- Final Output Check ------- #
if [ -z "$(find "$results" -maxdepth 1 -name "*.genes.results" 2>/dev/null)" ]; then
    log_error "No RSEM gene output files found in output directory."
    exit 1
fi
if [ $overall_status -eq 0 ]; then log_success "RSEM-STAR execution completed successfully."
else  log_error "One or more RSEM runs failed or were skipped. See warnings/errors above."; exit $overall_status; fi