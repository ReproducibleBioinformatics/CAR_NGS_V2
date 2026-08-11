#!/bin/bash
# ==============================================================================
# Master pipeline runner script for sequential module testing.
# Executes test.sh in each target module directory following the order defined
# by the pipeline workflow.
# ==============================================================================
DOCKER_NAME="test_all-v2"

NC='\033[0m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'
log_info() { echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} INFO]    ${1}${NC}"; }
log_step() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} PROCESS] ${1}${NC}"; }
log_warn() { echo -e "${ORANGE}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} WARNING] ${1}${NC}"; }
log_success() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} SUCCESS] ${1}${NC}"; }
log_error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [${DOCKER_NAME} ERROR]   ${1}${NC}"; }
log_sep() { echo -e "${2:-$CYAN}$(printf '%0.s'${1:-=} {1..100})${NC}"; }

# Base directory where test_all.sh is located
base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Target pipeline modules to be executed in sequence
modules=(
    "qc_report"
    "skewer"
    "rsemstarindex"
    "rsem"
    "annotated"
    "pca"
    "deseq2"
    "filter"
)

# ------- Print Pipeline Execution Context ------- #
log_sep "=" "$CYAN"
log_info "Pipeline Execution Context:"
echo -e "  ${CYAN}Runner Script   :${NC} ${GREEN}${DOCKER_NAME}${NC}"
echo -e "  ${CYAN}Base Directory  :${NC} ${YELLOW}${base_dir}${NC}"
echo -e "  ${CYAN}Total Modules   :${NC} ${YELLOW}${#modules[@]}${NC}"
log_sep "=" "$CYAN"
log_info "Initializing Master Sequential Pipeline Execution"

# ==============================================================================
# EXIT CODE SCHEME
# exit 1 -> execution failure of test.sh in any module step
# ==============================================================================

# ------- Core Processing Step: Sequential Module Loop ------- #
log_step "Executing sequential pipeline steps..."
log_sep

step_num=1
for mod in "${modules[@]}"; do
    mod_dir="${base_dir}/${mod}"

    # Handle fallback if 'rsem' directory is named 'rsemstar'
    if [ ! -d "$mod_dir" ] && [ "$mod" == "rsem" ] && [ -d "${base_dir}/rsemstar" ]; then
        mod_dir="${base_dir}/rsemstar"
    fi

    if [ ! -d "$mod_dir" ]; then
        log_warn "Module directory '${mod_dir}' does not exist. Skipping step ${step_num}."
        step_num=$((step_num + 1))
        continue
    fi

    test_script="${mod_dir}/test.sh"
    if [ ! -f "$test_script" ]; then
        log_warn "Test script '${test_script}' does not exist. Skipping step ${step_num}."
        step_num=$((step_num + 1))
        continue
    fi

    if [ ! -x "$test_script" ]; then
        chmod +x "$test_script"
    fi

    log_info "Step ${step_num}: Launching test.sh in module '${mod}'..."
    
    # Execute test.sh inside its module directory to preserve correct working context
    (
        cd "$mod_dir" || exit 1
        ./test.sh
    )
    cmd_exit_code=$?

    if [ $cmd_exit_code -ne 0 ]; then
        log_error "Execution of test.sh in module '${mod}' failed with exit code $cmd_exit_code."
        exit 1
    fi

    log_success "Step ${step_num}: Successfully completed module '${mod}'."
    log_sep "-" "$YELLOW"
    step_num=$((step_num + 1))
done

log_sep
log_success "Pipeline Terminated Successfully."