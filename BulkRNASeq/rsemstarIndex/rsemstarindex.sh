#!/usr/bin/env bash
set -euo pipefail

# ANSI color codes
RED='\033[91m'
WHITE='\033[97m'
YELLOW='\033[93m'
ORANGE='\033[38;5;208m'
GREEN='\033[92m'
RESET='\033[0m'

USAGE_STR=$(echo -e "${YELLOW}<workdir>${RESET}" "${YELLOW}<outdir>${RESET}" "${ORANGE}<fastafile>${RESET}" "${ORANGE}<gtffile>${RESET}" "${GREEN}<filter>${RESET}" "${GREEN}<chrom_pattern>${RESET}" "${GREEN}<threads>${RESET}" "${GREEN}<quiet>${RESET}")

if [ "$#" -ne 8 ]; then
    echo -e "${WHITE}Usage: bash rsemstarindex.sh ${USAGE_STR}${RESET}\n"
    echo -e "${YELLOW}This function executes the docker container rsem-star1 where RSEM and STAR are installed. The index is created using ENSEMBL genome fasta file.${RESET}\n"
    echo -e "${WHITE}Arguments:${RESET}"
    echo -e "${YELLOW}workdir        ${RESET} [io]  indicating the working folder"
    echo -e "${YELLOW}outdir         ${RESET} [out] indicating the scratch folder where docker container will be mounted"
    echo -e "${ORANGE}fastafile      ${RESET} [cp]  Contains the raw DNA sequence (chromosomes) of the reference genome, used by STAR as the blueprint for alignment"
    echo -e "${ORANGE}gtffile        ${RESET} [cp]  Contains the gene annotations (coordinates of exons, introns, and transcripts), used by RSEM to quantify gene expression."
    echo -e "${GREEN}filter         ${RESET}       Genome filtration strategy applied prior to indexing. Options: \'none\' (no filtering), \'all\' (removes long-name scaffolds and mitochondrial DNA), \'mito\' (removes mitochondrial DNA only), \'chrom\' (removes long-name scaffolds only)"
    echo -e "${GREEN}chrom_pattern  ${RESET}       Optional regex to override the default chromosome-naming pattern used to identify main chromosomes (e.g., \'^chr[0-9]+$\'). Use \'null\' to keep the default."
    echo -e "${GREEN}threads        ${RESET}       a number indicating the number of cores to be used from the application"
    echo -e "${GREEN}quiet          ${RESET}       Set to \"true\" to suppress tool processing messages, set to \"false\" to keep verbose logging enabled."
    exit 1
fi

# Parse positional arguments
workdir="${1}"
outdir="${2}"
fastafile="${3}"
gtffile="${4}"
filter="${5}"
chrom_pattern="${6}"
threads="${7}"
quiet="${8}"

# --- Input validation ---
errors=()

if [ ! -d "${workdir}" ]; then
    errors+=("Directory not found: workdir = ${workdir}")
fi
if [ ! -d "${outdir}" ]; then
    errors+=("Directory not found: outdir = ${outdir}")
fi
if [ ! -f "${fastafile}" ]; then
    errors+=("File not found: fastafile = ${fastafile}")
fi
if [ ! -f "${gtffile}" ]; then
    errors+=("File not found: gtffile = ${gtffile}")
fi
if ! echo "${filter}" | grep -qE "^(none|all|mito|chrom)$"; then
    errors+=("Invalid value for filter: ${filter}. Allowed: ['none', 'all', 'mito', 'chrom']")
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

# --- Bind files and service volumes ---
declare -A mounted_folders
_src_fastafile="$(realpath "${fastafile}")"
cp "${_src_fastafile}" "${scratch_path}/"
docker_vals["fastafile"]="/workDir/$(basename "${_src_fastafile}")"

_src_gtffile="$(realpath "${gtffile}")"
cp "${_src_gtffile}" "${scratch_path}/"
docker_vals["gtffile"]="/workDir/$(basename "${_src_gtffile}")"

docker_vals["filter"]="${filter}"
docker_vals["chrom_pattern"]="${chrom_pattern}"
docker_vals["threads"]="${threads}"
docker_vals["quiet"]="${quiet}"

mount_str="${mounts[*]}"
PARAM_NAMES=("filter" "chrom_pattern" "threads" "quiet")
special_chars_re='[;&|()<>$`"'"'"'[:space:]]'
cmd="docker run --rm ${mount_str} ghcr.io/reproduciblebioinformatics/docker4seq-rsemstarindex-v2:latest bash /home/start.sh <outdir> <fastafile> <gtffile> <filter> <threads> <chrom_pattern> <quiet>"
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