#!/bin/bash
DOCKER_NAME="rCASC2-demultiplexing-v1"

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
    echo -e "  $0 <input_dir> <out_dir> <samplesheet_file> <threads> <quiet>"
    echo ""
    echo -e "${YELLOW}Arguments (all mandatory):${NC}"
    echo -e "  ${CYAN}input_dir${NC}         Illumina run folder (must contain RunInfo.xml)"
    echo -e "  ${CYAN}out_dir${NC}           Output directory for the demultiplexed FASTQ files"
    echo -e "  ${CYAN}samplesheet_file${NC}  Path to the SampleSheet.csv file"
    echo -e "  ${CYAN}threads${NC}           Number of parallel threads (positive integer)"
    echo -e "  ${CYAN}quiet${NC}             Suppress processing log messages: 'true' or 'false'"
    log_sep "-" "$YELLOW"
}
# ------- Argument Checking All arguments are mandatory ------- #
if [ "$#" -ne 5 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then show_usage; exit 1; fi
# ------- Positional Arguments Assignment ------- #
input_dir="${1}"
out_dir="${2}"
samplesheet_file="${3}"
threads="${4}"
quiet="${5}"
# ------- Validate Quiet Parameter ------- #
if [ "$quiet" != "true" ] && [ "$quiet" != "false" ]; then log_warn "Invalid quiet parameter '$quiet', defaulting to 'false'"; quiet="false"; fi; QUIET="$quiet"
# ------- Print Pipeline Execution Context ------- #
if [ "$QUIET" == "false" ]; then
    log_sep "=" "$CYAN"
    log_info "Pipeline Execution Context:"
    echo -e "  ${CYAN}Docker Container:${NC} ${GREEN}${DOCKER_NAME}${NC}"
    echo -e "  ${CYAN}Input Dir       :${NC} ${YELLOW}${input_dir}${NC}"
    echo -e "  ${CYAN}Output Dir      :${NC} ${YELLOW}${out_dir}${NC}"
    echo -e "  ${CYAN}Samplesheet     :${NC} ${YELLOW}${samplesheet_file}${NC}"
    echo -e "  ${CYAN}Threads         :${NC} ${YELLOW}${threads}${NC}"
    echo -e "  ${CYAN}Quiet Mode      :${NC} ${YELLOW}${quiet}${NC}"
    log_sep "=" "$CYAN"
fi
# ------- Validate and Cap Threads Parameter ------- #
max_cores=$(nproc)
if ! [[ "$threads" =~ ^[0-9]+$ ]] || [ "$threads" -le 0 ]; then log_warn "Invalid threads parameter '$threads' (must be a positive integer). Defaulting to 1."; threads=1; fi
if [ "$threads" -gt "$max_cores" ]; then log_warn "Requested threads ($threads) exceed available CPU cores ($max_cores). Capping allocation to $max_cores."; threads=$max_cores; fi
# ------- Split Threads Budget across -r / -p / -w ------- #
# bcl2fastq exposes three independent thread knobs:
#   -r (--loading-threads)    : reading raw BCL files      -> I/O-bound, 1 thread is enough
#   -w (--writing-threads)    : writing compressed FASTQ    -> I/O-bound, 1 thread is enough
#   -p (--processing-threads) : demultiplexing/conversion   -> CPU-bound, gets the rest
r_threads=1
w_threads=1
if [ "$threads" -gt 2 ]; then
    p_threads=$((threads - r_threads - w_threads))
else
    p_threads=1
    log_warn "Threads budget ($threads) too low to dedicate separate loading/writing threads; -r/-w/-p will overlap on the same core(s)."
fi
log_info "Thread allocation -> -r ${r_threads}  -p ${p_threads}  -w ${w_threads}"
# ------- Check Output Directory ------- #
if [ ! -d "$out_dir" ]; then log_error "Output directory '$out_dir' does not exist."; exit 1; fi
if [ -n "$(find "$out_dir" -mindepth 1 -print -quit 2>/dev/null)" ]; then log_error "Output directory '$out_dir' is not empty. Terminating pipeline to prevent overwriting existing data."; exit 1; fi
# ------- Check Input Directory ------- #
if [ ! -d "$input_dir" ]; then log_error "Input directory '$input_dir' does not exist."; exit 1; fi
if [ ! -f "${input_dir}/RunInfo.xml" ]; then log_error "'${input_dir}' does not look like an Illumina run folder (RunInfo.xml not found)."; exit 1; fi
# ------- Check Samplesheet File ------- #
if [ ! -f "$samplesheet_file" ]; then log_error "Samplesheet file '$samplesheet_file' does not exist."; exit 1; fi
# ------- Running bcl2fastq ------- #
log_step "Running bcl2fastq..."
if [ "$QUIET" == "false" ]; then
    bcl2fastq \
        --runfolder-dir "$input_dir" \
        --output-dir "$out_dir" \
        --sample-sheet "$samplesheet_file" \
        --no-lane-splitting \
        --ignore-missing-bcls \
        --ignore-missing-filter \
        --ignore-missing-positions \
        --ignore-missing-controls \
        -r "$r_threads" -p "$p_threads" -w "$w_threads" \
        2>&1 | tee "${out_dir}/bcl2fastq.log"
    bcl2fastq_status=${PIPESTATUS[0]}
else
    bcl2fastq \
        --runfolder-dir "$input_dir" \
        --output-dir "$out_dir" \
        --sample-sheet "$samplesheet_file" \
        --no-lane-splitting \
        --ignore-missing-bcls \
        --ignore-missing-filter \
        --ignore-missing-positions \
        --ignore-missing-controls \
        -r "$r_threads" -p "$p_threads" -w "$w_threads" \
        > "${out_dir}/bcl2fastq.log" 2>&1
    bcl2fastq_status=$?
fi

if [ "$bcl2fastq_status" -eq 0 ]; then
    log_success "bcl2fastq completed successfully. Log saved to '${out_dir}/bcl2fastq.log'."
else
    log_error "bcl2fastq failed. Check the log at '${out_dir}/bcl2fastq.log' for details."
    exit 2
fi