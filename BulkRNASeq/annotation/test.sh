#!/bin/bash
SCRIPT_NAME="test-annotation"
NC='\033[0m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'; PINK='\033[1;35m'
log_test() { [ "$QUIET" == "true" ] && return; echo -e "${PINK}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} PROCESS] ${1}${NC}"; }
QUIET="$quiet"
get_latest_output_dir() {
    local base_dir="${1}"
    local max_num=-1
    local latest_dir=""
    if [ ! -d "$base_dir" ]; then  echo ""; return fi
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
workdir="workdir"
input_dir="../rsem/results"
results="results/"
annotation_file="../testdata/Genome/Drosophila_melanogaster.BDGP6.46.112.gtf"
gene_biotype="protein_coding"
metadata_sep=","
threads=8
quiet="false"
mkdir -p "$workdir" "$results"
input_dir=$(get_latest_output_dir "../rsemstar/results")
metadata="${input_dir}/sampleMetaData_rsemstar.csv"
log_test "Executing annotation pipeline via Python wrapper..."
python3 annotation.py "$workdir" "$input_dir" "$results" "$annotation_file" "$gene_biotype" "$metadata" "$metadata_sep" "$threads" "$quiet"