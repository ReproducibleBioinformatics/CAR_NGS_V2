#!/usr/bin/env bash
set -euo pipefail

# ANSI color codes
RED='\033[91m'
WHITE='\033[97m'
YELLOW='\033[93m'
ORANGE='\033[38;5;208m'
GREEN='\033[92m'
RESET='\033[0m'

USAGE_STR=$(echo -e "${YELLOW}<workdir>${RESET}" "${YELLOW}<inputdir>${RESET}" "${YELLOW}<outdir>${RESET}" "${ORANGE}<annotation_file>${RESET}" "${GREEN}<gene_biotype>${RESET}" "${ORANGE}<metadata>${RESET}" "${GREEN}<metadata_sep>${RESET}" "${GREEN}<threads>${RESET}" "${GREEN}<quiet>${RESET}")

if [ "$#" -ne 9 ]; then
    echo -e "${WHITE}Usage: bash annotation.sh ${USAGE_STR}${RESET}\n"
    echo -e "${YELLOW}This Docker image annotates RSEM genes.results output files with gene symbols/names retrieved from a matching GTF/GFF3 annotation file, batch-processing all samples in an input directory and writing the annotated TSV files to a specified output directory.${RESET}\n"
    echo -e "${WHITE}Arguments:${RESET}"
    echo -e "${YELLOW}workdir        ${RESET} [io]  indicating the working folder"
    echo -e "${YELLOW}inputdir       ${RESET} [in]  indicating where genes.results files are located"
    echo -e "${YELLOW}outdir         ${RESET} [out] indicating the folder where results will be written"
    echo -e "${ORANGE}annotation_file${RESET} [cp]  gene annotation file (GTF or GFF3 format) used to map gene IDs to gene names/symbols."
    echo -e "${GREEN}gene_biotype   ${RESET}       gene biotype"
    echo -e "${ORANGE}metadata       ${RESET} [cp]  A CSV or TSV file containing metadata for files in the input director"
    echo -e "${GREEN}metadata_sep   ${RESET}       File separator (use \",\" or \";\" for CSV, \"\t\" ora \"tab\" for TSV)"
    echo -e "${GREEN}threads        ${RESET}       a number indicating the number of cores to be used from the application"
    echo -e "${GREEN}quiet          ${RESET}       Set to \"true\" to suppress tool processing messages, set to \"false\" to keep verbose logging enabled."
    exit 1
fi

# Parse positional arguments
workdir="${1}"
inputdir="${2}"
outdir="${3}"
annotation_file="${4}"
gene_biotype="${5}"
metadata="${6}"
metadata_sep="${7}"
threads="${8}"
quiet="${9}"

# --- Input validation ---
errors=()

if [ ! -d "${workdir}" ]; then
    errors+=("Directory not found: workdir = ${workdir}")
fi
if [ ! -d "${inputdir}" ]; then
    errors+=("Directory not found: inputdir = ${inputdir}")
fi
if [ ! -d "${outdir}" ]; then
    errors+=("Directory not found: outdir = ${outdir}")
fi
if [ ! -f "${annotation_file}" ]; then
    errors+=("File not found: annotation_file = ${annotation_file}")
fi
if [ ! -f "${metadata}" ]; then
    errors+=("File not found: metadata = ${metadata}")
fi
if ! echo "${gene_biotype}" | grep -qE "^(protein_coding|unitary_pseudogene|unprocessed_pseudogene|processed_pseudogene|transcribed_unprocessed_pseudogene|processed_transcript|antisense|transcribed_unitary_pseudogene|polymorphic_pseudogene|lincRNA|sense_intronic|transcribed_processed_pseudogene|sense_overlapping|IG_V_pseudogene|pseudogene|TR_V_gene|3prime_overlapping_ncRNA|IG_V_gene|bidirectional_promoter_lncRNA|snRNA|miRNA|misc_RNA|snoRNA|rRNA|IG_C_gene|IG_J_gene|TR_J_gene|TR_C_gene|TR_V_pseudogene|TR_J_pseudogene|IG_D_gene|ribozyme|IG_C_pseudogene|TR_D_gene|TEC|IG_J_pseudogene|scRNA|scaRNA|vaultRNA|sRNA|macro_lncRNA|non_coding|IG_pseudogene)$"; then
    errors+=("Invalid value for gene_biotype: ${gene_biotype}. Allowed: ['protein_coding', 'unitary_pseudogene', 'unprocessed_pseudogene', 'processed_pseudogene', 'transcribed_unprocessed_pseudogene', 'processed_transcript', 'antisense', 'transcribed_unitary_pseudogene', 'polymorphic_pseudogene', 'lincRNA', 'sense_intronic', 'transcribed_processed_pseudogene', 'sense_overlapping', 'IG_V_pseudogene', 'pseudogene', 'TR_V_gene', '3prime_overlapping_ncRNA', 'IG_V_gene', 'bidirectional_promoter_lncRNA', 'snRNA', 'miRNA', 'misc_RNA', 'snoRNA', 'rRNA', 'IG_C_gene', 'IG_J_gene', 'TR_J_gene', 'TR_C_gene', 'TR_V_pseudogene', 'TR_J_pseudogene', 'IG_D_gene', 'ribozyme', 'IG_C_pseudogene', 'TR_D_gene', 'TEC', 'IG_J_pseudogene', 'scRNA', 'scaRNA', 'vaultRNA', 'sRNA', 'macro_lncRNA', 'non_coding', 'IG_pseudogene']")
fi
if ! echo "${metadata_sep}" | grep -qE "^(,|;|\\t|tab)$"; then
    errors+=("Invalid value for metadata_sep: ${metadata_sep}. Allowed: [',', ';', '\\t', 'tab']")
fi
if ! echo "${quiet}" | grep -qE "^(false|true)$"; then
    errors+=("Invalid value for quiet: ${quiet}. Allowed: ['false', 'true']")
fi

if [ "${#errors[@]}" -gt 0 ]; then
    for e in "${errors[@]}"; do
        echo -e "${RED}ERROR:${RESET} ${WHITE}${e}${RESET}"
    done
    exit 1
fi

# --- Scratch directory setup ---
n=1
while true; do
    if [ -d "$(realpath "${workdir}")/scratch${n}" ] || [ -d "$(realpath "${outdir}")/output${n}" ]; then
        n=$((n + 1))
    else
        break
    fi
done

scratch_path="$(realpath "${workdir}")/scratch${n}"
mkdir -p "${scratch_path}"
scratch_out_path="$(realpath "${outdir}")/output${n}"
mkdir -p "${scratch_out_path}"

# --- Build docker volume mounts ---
mounts=()
declare -A docker_vals
service_idx=1

mounts+=("-v \"${scratch_path}:/workDir\"")
docker_vals["workdir"]="/workDir"

mounts+=("-v \"${scratch_out_path}:/results\"")
docker_vals["outdir"]="/results"

# inputdir: read-write directory [in]
mounts+=("-v \"$(realpath "${inputdir}"):/data_results\"")
docker_vals["inputdir"]="/data_results"

# --- Bind files and service volumes ---
declare -A mounted_folders
_src_annotation_file="$(realpath "${annotation_file}")"
cp "${_src_annotation_file}" "${scratch_path}/"
docker_vals["annotation_file"]="/workDir/$(basename "${_src_annotation_file}")"

_src_metadata="$(realpath "${metadata}")"
cp "${_src_metadata}" "${scratch_path}/"
docker_vals["metadata"]="/workDir/$(basename "${_src_metadata}")"

docker_vals["gene_biotype"]="${gene_biotype}"
docker_vals["metadata_sep"]="${metadata_sep}"
docker_vals["threads"]="${threads}"
docker_vals["quiet"]="${quiet}"

mount_str="${mounts[*]}"
PARAM_NAMES=("gene_biotype" "metadata_sep" "threads" "quiet")
special_chars_re='[;&|()<>$`"'"'"'[:space:]]'
cmd="docker run --rm ${mount_str} ghcr.io/reproduciblebioinformatics/docker4seq-annotation-v2:latest bash /home/start.sh <workdir> <inputdir> <outdir> <annotation_file> <gene_biotype> <metadata> <metadata_sep> <threads> <quiet>"
for key in "${!docker_vals[@]}"; do
    val="${docker_vals[${key}]}"
    is_param=0
    for p_name in "${PARAM_NAMES[@]}"; do
        if [ "${key}" = "${p_name}" ]; then is_param=1; break; fi
    done
    if [ "${is_param}" -eq 1 ] && [[ "${val}" =~ ${special_chars_re} ]]; then
        escaped_val=$(echo "${val}" | sed 's/"/\\"/g')
        cmd="${cmd//<${key}>/\"${escaped_val}\"}"
    else
        cmd="${cmd//<${key}>/${val}}"
    fi
done
echo -e "\n${YELLOW}Running:${RESET}\n${WHITE}${cmd}${RESET}\n"
log_path="${scratch_path}/output_log.txt"
echo -e "${YELLOW}Log:${RESET} ${WHITE}${log_path}${RESET}\n"

eval "${cmd}" 2>&1 | tee "${log_path}"
exit_code=${PIPESTATUS[0]}

if [ "${exit_code}" -eq 0 ]; then
    echo -e "\n${GREEN}Done. Log saved to: ${log_path}${RESET}"
else
    echo -e "\n${RED}Docker exited with code ${exit_code}. See log: ${log_path}${RESET}"
fi
exit ${exit_code}