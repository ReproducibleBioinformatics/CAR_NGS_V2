#!/bin/bash
DOCKER_NAME="docker4seq-skewer-v2"

NC='\033[0m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'
log_info() { [ "$QUIET" == "true" ] && return; echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} INFO]    ${1}${NC}"; }
log_step() { [ "$QUIET" == "true" ] && return; echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} PROCESS] ${1}${NC}"; }
log_warn() { echo -e "${ORANGE}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} WARNING] ${1}${NC}"; }
log_success() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} SUCCESS] ${1}${NC}"; }
log_error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} ERROR]   ${1}${NC}"; }
log_sep() { echo -e "${2:-$CYAN}$(printf '%0.s'${1:-=} {1..100})${NC}"; }

show_usage() {
    log_sep "-" "$YELLOW"
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  $0 <inputDir> <outDir> <adapter5> <adapter3> <seq_type> <metadata> <separator> <threads> <quiet>"
    echo ""
    echo -e "${YELLOW}Arguments (all mandatory):${NC}"
    echo -e "  ${CYAN}inputDir${NC}    Base directory containing raw or structured FASTQ files"
    echo -e "  ${CYAN}outDir${NC}      Output directory for trimmed FASTQ results"
    echo -e "  ${CYAN}adapter5${NC}    5' adapter sequence"
    echo -e "  ${CYAN}adapter3${NC}    3' adapter sequence (required for PE; use 'none', 'null', or \"\" for SE)"
    echo -e "  ${CYAN}seq_type${NC}    Sequencing type: 'se' (Single-End) or 'pe' (Paired-End)"
    echo -e "  ${CYAN}metadata${NC}    Path to the metadata file containing sample names and folders"
    echo -e "  ${CYAN}separator${NC}   Field separator used in metadata (e.g., ';' or ','; default/other: tab)"
    echo -e "  ${CYAN}threads${NC}     Number of parallel threads (positive integer)"
    echo -e "  ${CYAN}quiet${NC}       Suppress processing log messages: 'true' or 'false'"
    log_sep "-" "$YELLOW"
}

if [ "$#" -ne 9 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_usage
    exit 1
fi

inputDir="${1}"
outDir="${2}"
adapter5="${3}"
adapter3="${4}"
seq_type="${5}"
metadata="${6}"
metadata_sep="${7}"
threads="${8}"
quiet="${9}"

log_sep "=" "$CYAN"
log_info "Pipeline Execution Context:"
echo -e "  ${CYAN}Docker Container:${NC} ${GREEN}${DOCKER_NAME}${NC}"
echo -e "  ${CYAN}Input FASTQ Dir :${NC} ${YELLOW}${inputDir}${NC}"
echo -e "  ${CYAN}Results Dir     :${NC} ${YELLOW}${outDir}${NC}"
echo -e "  ${CYAN}5' Adapter      :${NC} ${YELLOW}${adapter5}${NC}"
echo -e "  ${CYAN}3' Adapter      :${NC} ${YELLOW}${adapter3:-N/A}${NC}"
echo -e "  ${CYAN}Seq Type        :${NC} ${YELLOW}${seq_type}${NC}"
echo -e "  ${CYAN}Sample Metadata :${NC} ${YELLOW}${metadata}${NC}"
echo -e "  ${CYAN}Metadata Sep    :${NC} '${YELLOW}${metadata_sep}${NC}'"
echo -e "  ${CYAN}Threads Allocated:${NC}${YELLOW}${threads}${NC}"
echo -e "  ${CYAN}Quiet parameter:${NC}${YELLOW}${quiet}${NC}"
log_sep "=" "$CYAN"
log_info "Initializing Skewer Pipeline Wrapper"

# ------- Validate quiet parameter ------- #
if [ "$quiet" != "true" ] && [ "$quiet" != "false" ]; then
    log_error "The quiet parameter must be 'true' or 'false' (provided: '$quiet')"
    exit 1
fi
QUIET="$quiet"

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

# ------- Validate and normalize separator ------- #
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

# ------- Check input directories and metadata file ------- #
if [ ! -d "$inputDir" ]; then
    log_error "Data directory '$inputDir' does not exist."
    exit 1
fi

if [ ! -d "$outDir" ]; then
    log_error "Results directory '$outDir' does not exist."
    exit 1
fi

if [ -n "$(find "$outDir" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    log_error "Output directory '$outDir' is not empty. Terminating pipeline to prevent overwriting existing data."
    exit 1
fi

if [ ! -f "$metadata" ]; then
    log_error "Sample metadata file '$metadata' does not exist."
    exit 1
fi

# ------- Validate adapter sequences and sequence type ------- #
if [ -z "$adapter5" ]; then
    log_error "The 5' adapter sequence (adapter5) is required."
    exit 1
fi

DNA_REGEX="^[ACGTRYSWKMBDHVNacgtryswkmbdhvn]+$"
if [[ ! "$adapter5" =~ $DNA_REGEX ]]; then
    log_error "Invalid characters detected in adapter5 ('$adapter5'). Must contain valid DNA bases only."
    exit 1
fi
seq_type="${seq_type,,}"
if [ "$seq_type" == "pe" ] && [ -z "$adapter3" ]; then
    log_error "Paired-End (pe) mode requires both 5' and 3' adapters."
    exit 1
fi

if [ -n "$adapter3" ] && [ "$adapter3" != "none" ] && [ "$adapter3" != "null" ] && [[ ! "$adapter3" =~ $DNA_REGEX ]]; then
    log_error "Invalid characters detected in adapter3 ('$adapter3'). Must contain valid DNA bases only."
    exit 1
fi

if [ "$seq_type" != "se" ] && [ "$seq_type" != "pe" ]; then
    log_error "Invalid sequence type '$seq_type'. Must be 'se' or 'pe'."
    exit 1
fi

# ------- Validate Metadata via R script ------- #
log_step "Validating sample metadata content via R script..."
if ! Rscript /usr/local/bin/check_samplemetadata.R "$metadata" "${7}" "$seq_type" "${quiet,,}"; then
    log_error "Validation of metadata file failed. Terminating pipeline."
    exit 1
fi

# ------- Load Metadata into RAM (Associative Arrays) ------- #
log_step "Loading metadata into memory..."

declare -A COL_MAP
declare -A META_ROWS

header=$(head -n 1 "$metadata" | tr -d '\r')
IFS="$metadata_sep" read -ra cols <<< "$header"

for i in "${!cols[@]}"; do
    col_clean=$(echo "${cols[$i]}" | xargs | tr '[:upper:]' '[:lower:]')
    COL_MAP["$col_clean"]=$i
done

if [ -z "${COL_MAP["samplename"]}" ]; then
    log_error "Column 'SampleName' not found in metadata file."
    exit 1
fi

if [ -z "${COL_MAP["samplenumber"]}" ]; then
    log_error "Column 'SampleNumber' not found in metadata file."
    exit 1
fi

row_idx=0
while IFS="$metadata_sep" read -ra row; do
    [ ${#row[@]} -eq 0 ] && continue
    row_str=$(IFS="$metadata_sep"; echo "${row[*]}")
    META_ROWS["$row_idx"]="$row_str"
    ((row_idx++))
done < <(tail -n +2 "$metadata" | tr -d '\r')

log_info "Loaded ${#META_ROWS[@]} metadata entries into memory."

# Helper function to get field by row key and column name
get_field() {
    local key="$1"
    local col_name="$2"
    local c_idx="${COL_MAP[${col_name,,}]}"
    if [ -n "$c_idx" ]; then
        IFS="$metadata_sep" read -ra fields <<< "${META_ROWS[$key]}"
        echo "${fields[$c_idx]}" | xargs
    fi
}

# Helper function to update field by row key and column name
update_field() {
    local key="$1"
    local col_name="$2"
    local new_val="$3"
    local c_idx="${COL_MAP[${col_name,,}]}"
    if [ -n "$c_idx" ]; then
        IFS="$metadata_sep" read -ra fields <<< "${META_ROWS[$key]}"
        fields[$c_idx]="$new_val"
        META_ROWS["$key"]=$(IFS="$metadata_sep"; echo "${fields[*]}")
    fi
}

# ------- Sort Metadata Keys by SampleNumber ------- #
log_step "Sorting metadata entries by SampleNumber..."

SORTED_KEYS=()
while IFS= read -r key; do
    SORTED_KEYS+=("$key")
done < <(
    for key in "${!META_ROWS[@]}"; do
        snum=$(get_field "$key" "samplenumber")
        echo -e "${snum}\t${key}"
    done | sort -k1,1n | cut -f2
)

# ------- Processing Samples with Skewer ------- #
tmp_results="${outDir}/_tmp_skewer"
mkdir -p "$tmp_results"

updated_metadata="${tmp_results}/updated_metadata.tmp"
echo "$header" > "$updated_metadata"

log_step "Processing samples with Skewer ($seq_type mode)..."
log_sep

i=0
total_samples=${#SORTED_KEYS[@]}

while [ $i -lt $total_samples ]; do
    key1="${SORTED_KEYS[$i]}"
    snum1=$(get_field "$key1" "samplenumber")
    sname1=$(get_field "$key1" "samplename")
    sfolder1=$(get_field "$key1" "samplefolder")

    if [ -z "$sname1" ]; then
        ((i++))
        continue
    fi

    # Build file target path 1
    if [ -n "$sfolder1" ]; then
        target1="${inputDir}/${sfolder1}/${sname1}"
        prefix1="$(echo "$sfolder1" | tr '/' '_')_"
    else
        target1="${inputDir}/${sname1}"
        prefix1=""
    fi

    if [ "$seq_type" == "se" ]; then
        # ------------------- Single-End Processing ------------------- #
        if [ ! -f "$target1" ]; then
            log_warn "File not found: '$target1'. Skipping."
            ((i++))
            continue
        fi

        log_info "Running Skewer [SE]: $target1"

        base1=$(basename "$sname1")
        out_prefix="se_snum_${snum1}"  
        new_sname1="${prefix1}${base1}"
        
        if skewer --quiet -z -x "$adapter5" -m any -t "$threads" -l 18 -o "${tmp_results}/${out_prefix}" "$target1"; then
            if [ -f "${tmp_results}/${out_prefix}-trimmed.fastq.gz" ]; then
                mv "${tmp_results}/${out_prefix}-trimmed.fastq.gz" "${outDir}/${new_sname1}"
                rm -f "${tmp_results}/${out_prefix}-trimmed.log" 2>/dev/null
                log_success "Generated SE output: '${new_sname1}'"

                update_field "$key1" "samplename" "$new_sname1"
                [ -n "${COL_MAP["samplefolder"]}" ] && update_field "$key1" "samplefolder" ""

                echo "${META_ROWS[$key1]}" >> "$updated_metadata"
            fi
        else
            log_error "Skewer processing failed for: $target1"
        fi

        ((i++))

    elif [ "$seq_type" == "pe" ]; then
        # ------------------- Paired-End Processing ------------------- #
        next_idx=$((i + 1))
        
        if [ $next_idx -ge $total_samples ]; then
            log_warn "Unpaired sample at end of metadata (SampleNumber: $snum1, File: $sname1). Skipping."
            ((i++))
            continue
        fi

        key2="${SORTED_KEYS[$next_idx]}"
        snum2=$(get_field "$key2" "samplenumber")
        sname2=$(get_field "$key2" "samplename")
        sfolder2=$(get_field "$key2" "samplefolder")

        # Check if pair matches SampleNumber
        if [ "$snum1" != "$snum2" ]; then
            log_warn "Mismatch in SampleNumber for PE pair: '$snum1' vs '$snum2' (File: $sname1). Skipping."
            ((i++))
            continue
        fi

        # Build file target path 2
        if [ -n "$sfolder2" ]; then
            target2="${inputDir}/${sfolder2}/${sname2}"
            prefix2="$(echo "$sfolder2" | tr '/' '_')_"
        else
            target2="${inputDir}/${sname2}"
            prefix2=""
        fi

        if [ ! -f "$target1" ] || [ ! -f "$target2" ]; then
            log_warn "Missing FASTQ file(s) for pair ($sname1 / $sname2). Skipping."
            i=$((i + 2))
            continue
        fi

        log_info "Running Skewer [PE]: '$sname1' and '$sname2' (SampleNumber: $snum1)"

        base1=$(basename "$sname1")
        base2=$(basename "$sname2")

        new_sname1="${prefix1}${base1}"
        new_sname2="${prefix2}${base2}"

        out_prefix="pe_snum_${snum1}"

        if skewer --quiet -z -x "$adapter5" -y "$adapter3" -m pe -t "$threads" -l 18 -o "${tmp_results}/${out_prefix}" "$target1" "$target2"; then
            trim1="${tmp_results}/${out_prefix}-trimmed-pair1.fastq.gz"
            trim2="${tmp_results}/${out_prefix}-trimmed-pair2.fastq.gz"

            if [ -f "$trim1" ] && [ -f "$trim2" ]; then
                mv "$trim1" "${outDir}/${new_sname1}"
                mv "$trim2" "${outDir}/${new_sname2}"
                rm -f "${tmp_results}/${out_prefix}-trimmed.log" 2>/dev/null
                log_success "Generated PE outputs: '${new_sname1}' and '${new_sname2}'"

                update_field "$key1" "samplename" "$new_sname1"
                update_field "$key2" "samplename" "$new_sname2"

                if [ -n "${COL_MAP["samplefolder"]}" ]; then
                    update_field "$key1" "samplefolder" ""
                    update_field "$key2" "samplefolder" ""
                fi

                echo "${META_ROWS[$key1]}" >> "$updated_metadata"
                echo "${META_ROWS[$key2]}" >> "$updated_metadata"
            fi
        else
            log_error "Skewer processing failed for PE pair: $sname1 / $sname2"
        fi

        # Advance index by 2 for Paired-End
        i=$((i + 2))
    fi
done

# ------- Save Updated Metadata File with Matching Extension ------- #
metadata_filename=$(basename "$metadata")
base_meta_name="${metadata_filename%.*}"

if [ "$metadata_sep" == $'\t' ]; then
    target_ext="tsv"
else
    target_ext="csv"
fi

out_metadata_filename="${base_meta_name}_skewer.${target_ext}"

if [ -f "$updated_metadata" ]; then
    mv "$updated_metadata" "${outDir}/${out_metadata_filename}"
    log_info "Saved updated metadata to '${outDir}/${out_metadata_filename}'"
fi

# Clean up temporary directory
rm -rf "$tmp_results"

# Check if any outputs were produced
if [ -z "$(find "$outDir" -maxdepth 1 -name "*.fastq.gz" 2>/dev/null)" ]; then
    log_error "No trimmed FASTQ outputs found in output directory."
    exit 1
fi

log_sep
log_success "Pipeline Terminated Successfully."