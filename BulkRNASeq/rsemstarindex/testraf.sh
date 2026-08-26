#!/bin/bash
SCRIPT_NAME="test-rsemstarindex"
workdir="workdir"
results="results/"
genome_fa="../testraf/Genome/Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz"
gtf_file="../testraf/Genome/Homo_sapiens.GRCh38.116.gtf.gz"
mito_pattern="all"
chrom_pattern='null'
threads=5
quiet="false"
mkdir -p "$workdir" "$results"
NC='\033[0m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'; PINK='\033[1;35m'
log_test() { [ "$QUIET" == "true" ] && return; echo -e "${PINK}[$(date '+%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME} PROCESS] ${1}${NC}"; }
QUIET="$quiet"
python3 rsemstarindex.py "$workdir" "$results" "$genome_fa" "$gtf_file" "$mito_pattern" "$chrom_pattern" "$threads" "$quiet"