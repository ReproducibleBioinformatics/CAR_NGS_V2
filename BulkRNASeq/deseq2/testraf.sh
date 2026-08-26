#!/bin/bash
SCRIPT_NAME="test-deseq2"
workdir="workdir"
results="results/"
log2fc=0.585
fdr=0.05
ref_covar="s"
target_covar="r"
metadata_sep=","
matrix_sep="tab"
threads=8
quiet="false"
mkdir -p "$workdir" "$results"
NC='\033[0m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'; PINK='\033[1;35m'
log_test() { [ "$QUIET" == "true" ] && return; echo -e "${PINK}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} PROCESS] ${1}${NC}"; }
QUIET="$quiet"
mkdir -p "$workdir" "$results"
# ------- Function to Find Highest Output Directory ------- #
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
input_dir=$(get_latest_output_dir "../annotation/results")
metadata="${input_dir}/sampleMetaData_annotation.csv"
matrix_path="${input_dir}/experiment_counts.txt"
log_test "Executing deseq2 pipeline via Python wrapper..."
python3 deseq2.py "$workdir" "$results" "$matrix_path" "$matrix_sep" "$metadata" "$metadata_sep" "$log2fc" "$fdr" "$ref_covar" "$target_covar" "$threads" "$quiet"