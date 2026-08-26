#!/bin/bash
SCRIPT_NAME="test-filter"
NC='\033[0m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'; PINK='\033[1;35m'
log_test() { [ "$QUIET" == "true" ] && return; echo -e "${PINK}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} PROCESS] ${1}${NC}"; }
workdir="workdir"
results="results/"
log2fc=0.585
padj="0.05"
threads=8
quiet="false"
mkdir -p "$workdir" "$results"
QUIET="$quiet"
get_latest_output_dir() {
    local base_dir="${1}"
    local max_num=-1
    local latest_dir=""
    if [ ! -d "$base_dir" ]; then echo ""; return; fi
    for dir in "${base_dir}"/output*; do
        if [ -d "$dir" ]; then
            folder_name=$(basename "$dir")
            num="${folder_name#output}"
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -gt "$max_num" ]; then
                max_num=$num
                latest_dir="$dir"
            fi
        fi
    done
    echo "$latest_dir"
}
input_dir=$(get_latest_output_dir "../deseq2/results")
de_full="${input_dir}/DE_FULL.txt"
raw_counts="${input_dir}/experiment_counts_DE.txt"
norm_counts="${input_dir}/experiment_counts_normalized_DE.txt"
log_test "Executing Filter pipeline via Python wrapper..."
python3 filter.py "$workdir" "$results" "$de_full" "$raw_counts" "$norm_counts" "$log2fc" "$padj" "$threads" "$quiet"