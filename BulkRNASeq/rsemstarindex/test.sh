#!/bin/bash
SCRIPT_NAME="test-rsemstarindex"
workdir="workdir"
results="results/"
genome_fa="../testdata/Genome/Drosophila_melanogaster.BDGP6.46.dna.toplevel.fa"
gtf_file="../testdata/Genome/Drosophila_melanogaster.BDGP6.46.112.gtf"
mito_pattern="mito"
chrom_pattern='^(2L|2R|3L|3R|4|X|Y)$'
threads=8
quiet="false"
mkdir -p "$workdir" "$results"
NC='\033[0m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'; PINK='\033[1;35m'
log_test() { [ "$QUIET" == "true" ] && return; echo -e "${PINK}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} PROCESS] ${1}${NC}"; }
QUIET="$quiet"
python3 rsemstarindex.py "$workdir" "$results" "$genome_fa" "$gtf_file" "$mito_pattern" "$chrom_pattern" "$threads" "$quiet"