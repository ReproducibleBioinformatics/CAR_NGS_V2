#!/bin/bash
DOCKER_NAME="rCASC2-cellrangerindex-v2"

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
    echo -e "  $0 <out_dir> <fasta_file> <gtf_file> <gene_biotype> <threads> <quiet>"
    echo ""
    echo -e "${YELLOW}Arguments (all mandatory):${NC}"
    echo -e "  ${CYAN}out_dir${NC}         Output directory where the cellranger reference will be written"
    echo -e "  ${CYAN}fasta_file${NC}      Path to the reference genome FASTA file"
    echo -e "  ${CYAN}gtf_file${NC}        Path to the gene annotation GTF file"
    echo -e "  ${CYAN}gene_biotype${NC}    Gene biotype to keep when filtering the GTF ('all' to skip filtering)"
    echo -e "  ${CYAN}max_memory${NC}      Maximum amount of memory (RAM) that Cell Ranger is allowed to use."
    echo -e "  ${CYAN}threads${NC}         Number of parallel threads (positive integer)"
    echo -e "  ${CYAN}quiet${NC}           Suppress processing log messages: 'true' or 'false'"
    log_sep "-" "$YELLOW"
}
# ------- Argument Checking All arguments are mandatory ------- #
if [ "$#" -ne 7 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then show_usage; exit 1; fi
# ------- Positional Arguments Assignment ------- #
out_dir="${1}"
fasta_file="${2}"
gtf_file="${3}"
gene_biotype="${4}"
max_memory="${5}"
threads="${6}"
quiet="${7}"
# ------- Validate Quiet Parameter ------- #
if [ "$quiet" != "true" ] && [ "$quiet" != "false" ]; then log_warn "Invalid quiet parameter '$quiet', defaulting to 'false'"; quiet="false"; fi; QUIET="$quiet"
# ------- Print Pipeline Execution Context ------- #
if [ "$QUIET" == "false" ]; then
    log_sep "=" "$CYAN"
    log_info "Pipeline Execution Context:"
    echo -e "  ${CYAN}Docker Container:${NC} ${GREEN}${DOCKER_NAME}${NC}"
    echo -e "  ${CYAN}Output Dir      :${NC} ${YELLOW}${out_dir}${NC}"
    echo -e "  ${CYAN}Fasta File      :${NC} ${YELLOW}${fasta_file}${NC}"
    echo -e "  ${CYAN}GTF File        :${NC} ${YELLOW}${gtf_file}${NC}"
    echo -e "  ${CYAN}Gene Biotype    :${NC} ${YELLOW}${gene_biotype}${NC}"
    echo -e "  ${CYAN}Max memory      :${NC} ${YELLOW}${max_memory}${NC}"
    echo -e "  ${CYAN}Threads         :${NC} ${YELLOW}${threads}${NC}"
    echo -e "  ${CYAN}Quiet Mode      :${NC} ${YELLOW}${quiet}${NC}"
    log_sep "=" "$CYAN"
fi
# ------- Validate and Cap Threads Parameter ------- #
max_cores=$(nproc)
if ! [[ "$threads" =~ ^[0-9]+$ ]] || [ "$threads" -le 0 ]; then log_warn "Invalid threads parameter '$threads' (must be a positive integer). Defaulting to 1."; threads=1; fi
if [ "$threads" -gt "$max_cores" ]; then log_warn "Requested threads ($threads) exceed available CPU cores ($max_cores). Capping allocation to $max_cores."; threads=$max_cores; fi
log_info "Thread allocation -> --nthreads ${threads}"
# ------- Validate max_memory Parameter and Cap Against Available RAM ------- #
if ! [[ "$max_memory" =~ ^[0-9]+$ ]] || [ "$max_memory" -le 0 ]; then log_warn "Invalid max_memory parameter '$max_memory' (must be a positive integer, in GB). Defaulting to 16 GB."; max_memory=16; fi
avail_mem_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
avail_mem_gb=$((avail_mem_kb / 1024 / 1024))
usable_mem_gb=$((avail_mem_gb - 2))
mem_gb=$max_memory
if [ "$max_memory" -gt "$usable_mem_gb" ]; then log_warn "Requested max_memory (${max_memory} GB) exceeds safely available system memory (${avail_mem_gb} GB available, ${safety_margin_gb} GB reserved as safety margin). Capping --memgb to ${usable_mem_gb} GB."; mem_gb=$usable_mem_gb; fi
if [ "$mem_gb" -lt 1 ]; then log_error "Not enough available memory (${avail_mem_gb} GB) to safely run cellranger mkref."; exit 1; fi
log_info "Memory allocation -> --memgb ${mem_gb} (requested: ${max_memory} GB, available: ${avail_mem_gb} GB)"
# ------- Check Output Directory ------- #
if [ ! -d "$out_dir" ]; then log_error "Output directory '$out_dir' does not exist."; exit 1; fi
if [ -n "$(find "$out_dir" -mindepth 1 -print -quit 2>/dev/null)" ]; then log_error "Output directory '$out_dir' is not empty. Terminating pipeline to prevent overwriting existing data."; exit 1; fi
# ------- Check Fasta File ------- #
if [ ! -f "$fasta_file" ]; then log_error "Fasta file '$fasta_file' does not exist."; exit 1; fi
# ------- Check GTF File ------- #
if [ ! -f "$gtf_file" ]; then log_error "GTF file '$gtf_file' does not exist."; exit 1; fi
# ------- Validate Gene Biotype Parameter ------- #
valid_biotypes=("all" "protein_coding" "unitary_pseudogene" "unprocessed_pseudogene" "processed_pseudogene" \
    "transcribed_unprocessed_pseudogene" "processed_transcript" "antisense" "transcribed_unitary_pseudogene" \
    "polymorphic_pseudogene" "lincRNA" "sense_intronic" "transcribed_processed_pseudogene" "sense_overlapping" \
    "IG_V_pseudogene" "pseudogene" "TR_V_gene" "3prime_overlapping_ncRNA" "IG_V_gene" "bidirectional_promoter_lncRNA" \
    "snRNA" "miRNA" "misc_RNA" "snoRNA" "rRNA" "IG_C_gene" "IG_J_gene" "TR_J_gene" "TR_C_gene" "TR_V_pseudogene" \
    "TR_J_pseudogene" "IG_D_gene" "ribozyme" "IG_C_pseudogene" "TR_D_gene" "TEC" "IG_J_pseudogene" "scRNA" \
    "scaRNA" "vaultRNA" "sRNA" "macro_lncRNA" "non_coding" "IG_pseudogene")
biotype_ok="false"
for b in "${valid_biotypes[@]}"; do
    if [ "$b" == "$gene_biotype" ]; then biotype_ok="true"; break; fi
done
if [ "$biotype_ok" != "true" ]; then log_error "Invalid gene_biotype parameter '$gene_biotype'."; exit 1; fi

# ------- Derive genome name from fasta filename ------- #
genome_name="$(basename "$fasta_file")"
genome_name="${genome_name%%.*}"

# ------- Resolve absolute paths (cellranger writes into the current directory) ------- #
fasta_file="$(readlink -f "$fasta_file")"
gtf_file="$(readlink -f "$gtf_file")"
out_dir="$(readlink -f "$out_dir")"
# ------- Set stdout redirection for cellranger based on 'quiet' ------- #
cr_stdout_redirect="/dev/stdout"
if [ "$QUIET" == "true" ]; then cr_stdout_redirect="${out_dir}/cellrangerindex.log"; export PYTHONWARNINGS="ignore::SyntaxWarning"; fi
# ------- Filter GTF by gene_biotype (skipped when 'all') ------- #
gtf_for_mkref="$gtf_file"
if [ "$gene_biotype" != "all" ]; then
    log_step "Filtering GTF by gene_biotype '${gene_biotype}' with cellranger mkgtf..."
    filtered_gtf="${out_dir}/${genome_name}.filtered.gtf"
    cellranger mkgtf \
        "$gtf_file" \
        "$filtered_gtf" \
        --attribute=gene_biotype:"$gene_biotype" \
        > "$cr_stdout_redirect"
    mkgtf_status=$?
    if [ "$mkgtf_status" -ne 0 ]; then
        log_error "cellranger mkgtf failed (exit code ${mkgtf_status})."
        exit 2
    fi
    gtf_for_mkref="$filtered_gtf"
    log_success "GTF filtering completed successfully."
else
    log_info "gene_biotype='all', skipping GTF filtering step."
fi

# ------- Running cellranger mkref (single execution point, no log file) ------- #
log_step "Running cellranger mkref..."
cd "$out_dir" || { log_error "Unable to cd into output directory '${out_dir}'."; exit 1; }
cellranger mkref \
    --genome="$genome_name" \
    --fasta="$fasta_file" \
    --genes="$gtf_for_mkref" \
    --nthreads="$threads" \
    --memgb="$mem_gb" \
    > "$cr_stdout_redirect"
cellranger_status=$?

if [ "$cellranger_status" -eq 0 ]; then
    log_success "cellranger mkref completed successfully."
else
    log_error "cellranger mkref failed (exit code ${cellranger_status})."
    exit 2
fi
