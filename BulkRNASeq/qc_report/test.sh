#!/bin/bash
SCRIPT_NAME="test-qcreport"
workdir="workdir"
input_dir="../testdata/raw_data/"
results="results/"
metadata="../testdata/raw_data/sampleMetaData.csv"
metadata_sep=","
threads=10
quiet="false"
NC='\033[0m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'; PINK='\033[1;35m'
log_test() { [ "$QUIET" == "true" ] && return; echo -e "${PINK}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} PROCESS] ${1}${NC}"; }
QUIET="$quiet"
mkdir -p "$workdir" "$results"
log_test "Executing QC Report pipeline via Python wrapper..."
python3 qc_report.py "$workdir" "$input_dir" "$results" "$metadata" "$metadata_sep" "$threads" "$quiet"