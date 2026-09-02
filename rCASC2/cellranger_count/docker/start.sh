#!/bin/bash
DOCKER_NAME="rCASC2-cellrangercount-v2"

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
    echo -e "  $0 <outDir> <transcriptome> <fastqs> <chemistry> <expect_cells> <force_cells> <nosecondary> <r1length> <r2length> <lanes> <save_bam> <max_memory> <threads> <quiet>"
    echo ""
    echo -e "${YELLOW}Arguments (all mandatory, pass 'NULL' to skip optional ones):${NC}"
    echo -e "  ${CYAN}outDir${NC}          Output directory where cellranger count results will be written"
    echo -e "  ${CYAN}transcriptome${NC}   Path to reference genome/transcriptome directory"
    echo -e "  ${CYAN}fastqs${NC}          Path to input directory containing raw FASTQ files"
    echo -e "  ${CYAN}chemistry${NC}       Library assay configuration ('auto', 'threeprime', 'fiveprime', 'SC3Pv1', 'SC3Pv2', 'SC3Pv3', 'SC5P-PE', 'SC5P-R2', 'ARC-v1')"
    echo -e "  ${CYAN}expect_cells${NC}    Expected number of recovered cells (positive integer or 'NULL')"
    echo -e "  ${CYAN}force_cells${NC}     Force fixed number of detected cells (positive integer or 'NULL')"
    echo -e "  ${CYAN}nosecondary${NC}     Disable secondary analyses ('true', 'false', or 'NULL')"
    echo -e "  ${CYAN}r1length${NC}        Hard-trim Read 1 sequence length (positive integer or 'NULL')"
    echo -e "  ${CYAN}r2length${NC}        Hard-trim Read 2 sequence length (positive integer or 'NULL')"
    echo -e "  ${CYAN}lanes${NC}           Comma-separated flowcell lane numbers or single lane (e.g. '1', '1,2', or 'NULL')"
    echo -e "  ${CYAN}save_bam${NC}        Enable BAM alignment file generation ('true' or 'false')"
    echo -e "  ${CYAN}max_memory${NC}      Maximum amount of RAM (in GB) allowed for Cell Ranger"
    echo -e "  ${CYAN}threads${NC}         Number of parallel CPU threads (positive integer)"
    echo -e "  ${CYAN}quiet${NC}           Suppress processing log messages ('true' or 'false')"
    log_sep "-" "$YELLOW"
}

# ------- Argument Checking All 14 arguments are mandatory ------- #
if [ "$#" -ne 14 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then show_usage; exit 1; fi

# ------- Positional Arguments Assignment ------- #
outDir="${1}"
transcriptome="${2}"
fastqs="${3}"
chemistry="${4}"
expect_cells="${5}"
force_cells="${6}"
nosecondary="${7}"
r1length="${8}"
r2length="${9}"
lanes="${10}"
save_bam="${11}"
max_memory="${12}"
threads="${13}"
quiet="${14}"

# ------- Validate Quiet Parameter ------- #
if [ "$quiet" != "true" ] && [ "$quiet" != "false" ]; then log_warn "Invalid quiet parameter '$quiet', defaulting to 'false'"; quiet="false"; fi; QUIET="$quiet"

# ------- Print Pipeline Execution Context ------- #
if [ "$QUIET" == "false" ]; then
    log_sep "=" "$CYAN"
    log_info "Pipeline Execution Context:"
    echo -e "  ${CYAN}Docker Container:${NC} ${GREEN}${DOCKER_NAME}${NC}"
    echo -e "  ${CYAN}Output Dir      :${NC} ${YELLOW}${outDir}${NC}"
    echo -e "  ${CYAN}Transcriptome   :${NC} ${YELLOW}${transcriptome}${NC}"
    echo -e "  ${CYAN}FASTQs Dir      :${NC} ${YELLOW}${fastqs}${NC}"
    echo -e "  ${CYAN}Chemistry       :${NC} ${YELLOW}${chemistry}${NC}"
    echo -e "  ${CYAN}Expect Cells    :${NC} ${YELLOW}${expect_cells}${NC}"
    echo -e "  ${CYAN}Force Cells     :${NC} ${YELLOW}${force_cells}${NC}"
    echo -e "  ${CYAN}No Secondary    :${NC} ${YELLOW}${nosecondary}${NC}"
    echo -e "  ${CYAN}Read 1 Length   :${NC} ${YELLOW}${r1length}${NC}"
    echo -e "  ${CYAN}Read 2 Length   :${NC} ${YELLOW}${r2length}${NC}"
    echo -e "  ${CYAN}Lanes           :${NC} ${YELLOW}${lanes}${NC}"
    echo -e "  ${CYAN}Save BAM        :${NC} ${YELLOW}${save_bam}${NC}"
    echo -e "  ${CYAN}Max Memory      :${NC} ${YELLOW}${max_memory}${NC}"
    echo -e "  ${CYAN}Threads         :${NC} ${YELLOW}${threads}${NC}"
    echo -e "  ${CYAN}Quiet Mode      :${NC} ${YELLOW}${quiet}${NC}"
    log_sep "=" "$CYAN"
fi

# ------- Validate and Cap Threads Parameter ------- #
max_cores=$(nproc)
if ! [[ "$threads" =~ ^[0-9]+$ ]] || [ "$threads" -le 0 ]; then log_warn "Invalid threads parameter '$threads' (must be a positive integer). Defaulting to 1."; threads=1; fi
if [ "$threads" -gt "$max_cores" ]; then log_warn "Requested threads ($threads) exceed available CPU cores ($max_cores). Capping allocation to $max_cores."; threads=$max_cores; fi
log_info "Thread allocation -> --localcores ${threads}"

# ------- Validate max_memory Parameter and Cap Against Available RAM ------- #
if ! [[ "$max_memory" =~ ^[0-9]+$ ]] || [ "$max_memory" -le 0 ]; then log_warn "Invalid max_memory parameter '$max_memory' (must be a positive integer, in GB). Defaulting to 16 GB."; max_memory=16; fi
avail_mem_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
avail_mem_gb=$((avail_mem_kb / 1024 / 1024))
usable_mem_gb=$((avail_mem_gb - 2))
mem_gb=$max_memory
if [ "$max_memory" -gt "$usable_mem_gb" ]; then log_warn "Requested max_memory (${max_memory} GB) exceeds safely available system memory (${avail_mem_gb} GB available, 2 GB reserved as safety margin). Capping --localmem to ${usable_mem_gb} GB."; mem_gb=$usable_mem_gb; fi
if [ "$mem_gb" -lt 1 ]; then log_error "Not enough available memory (${avail_mem_gb} GB) to safely run cellranger count."; exit 1; fi
log_info "Memory allocation -> --localmem ${mem_gb} (requested: ${max_memory} GB, available: ${avail_mem_gb} GB)"

# ------- Check Input Directories ------- #
if [ ! -d "$outDir" ]; then log_error "Output directory '$outDir' does not exist."; exit 1; fi
if [ ! -d "$transcriptome" ]; then log_error "Transcriptome directory '$transcriptome' does not exist."; exit 1; fi
if [ ! -d "$fastqs" ]; then log_error "FASTQs directory '$fastqs' does not exist."; exit 1; fi

# ------- Validate Chemistry Parameter ------- #
valid_chemistries=("auto" "threeprime" "fiveprime" "SC3Pv1" "SC3Pv2" "SC3Pv3" "SC5P-PE" "SC5P-R2" "ARC-v1")
chem_ok="false"
for c in "${valid_chemistries[@]}"; do
    if [ "$c" == "$chemistry" ]; then chem_ok="true"; break; fi
done
if [ "$chem_ok" != "true" ]; then log_error "Invalid chemistry parameter '$chemistry'. Must be one of: ${valid_chemistries[*]}"; exit 1; fi

# ------- Validate Save BAM Parameter ------- #
if [ "$save_bam" != "true" ] && [ "$save_bam" != "false" ]; then
    log_warn "Invalid save_bam parameter '$save_bam' (must be 'true' or 'false'). Defaulting to 'true'."
    save_bam="true"
fi

# ------- Validate Optional Parameters ------- #
if [ "$expect_cells" != "NULL" ] && (! [[ "$expect_cells" =~ ^[0-9]+$ ]] || [ "$expect_cells" -le 0 ]); then
    log_error "Invalid expect_cells parameter '$expect_cells' (must be a positive integer or 'NULL')."
    exit 1
fi

if [ "$force_cells" != "NULL" ] && (! [[ "$force_cells" =~ ^[0-9]+$ ]] || [ "$force_cells" -le 0 ]); then
    log_error "Invalid force_cells parameter '$force_cells' (must be a positive integer or 'NULL')."
    exit 1
fi

if [ "$r1length" != "NULL" ] && (! [[ "$r1length" =~ ^[0-9]+$ ]] || [ "$r1length" -le 0 ]); then
    log_error "Invalid r1length parameter '$r1length' (must be a positive integer or 'NULL')."
    exit 1
fi

if [ "$r2length" != "NULL" ] && (! [[ "$r2length" =~ ^[0-9]+$ ]] || [ "$r2length" -le 0 ]); then
    log_error "Invalid r2length parameter '$r2length' (must be a positive integer or 'NULL')."
    exit 1
fi

# ------- Resolve Absolute Paths ------- #
outDir="$(readlink -f "$outDir")"
transcriptome="$(readlink -f "$transcriptome")"
fastqs="$(readlink -f "$fastqs")"

# ------- Set stdout redirection based on 'quiet' ------- #
cr_stdout_redirect="/dev/stdout"
if [ "$QUIET" == "true" ]; then cr_stdout_redirect="${outDir}/cellrangercount.log"; export PYTHONWARNINGS="ignore::SyntaxWarning"; fi

# ------- Construct Cell Ranger CLI Flags Array ------- #
cmd_args=(
    "--id=results_cellranger"
    "--transcriptome=${transcriptome}"
    "--fastqs=${fastqs}"
    "--chemistry=${chemistry}"
    "--create-bam=${save_bam}"
    "--localcores=${threads}"
    "--localmem=${mem_gb}"
)

if [ "$expect_cells" != "NULL" ]; then cmd_args+=("--expect-cells=${expect_cells}"); fi
if [ "$force_cells" != "NULL" ]; then cmd_args+=("--force-cells=${force_cells}"); fi
if [ "$nosecondary" == "true" ]; then cmd_args+=("--nosecondary"); fi
if [ "$r1length" != "NULL" ]; then cmd_args+=("--r1-length=${r1length}"); fi
if [ "$r2length" != "NULL" ]; then cmd_args+=("--r2-length=${r2length}"); fi
if [ "$lanes" != "NULL" ]; then cmd_args+=("--lanes=${lanes}"); fi

# ------- Execute cellranger count ------- #
log_step "Running cellranger count..."
cd "$outDir" || { log_error "Unable to cd into output directory '${outDir}'."; exit 1; }

cellranger count "${cmd_args[@]}" > "$cr_stdout_redirect" 2>&1
cellranger_status=$?

if [ "$cellranger_status" -eq 0 ]; then
    log_success "cellranger count completed successfully."
else
    log_error "cellranger count failed (exit code ${cellranger_status})."
    exit 2
fi