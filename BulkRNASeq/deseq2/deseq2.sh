#!/usr/bin/env bash
set -euo pipefail

# ANSI color codes
RED='\033[91m'
WHITE='\033[97m'
YELLOW='\033[93m'
ORANGE='\033[38;5;208m'
GREEN='\033[92m'
RESET='\033[0m'

USAGE_STR=$(echo -e "${YELLOW}<workdir>${RESET}" "${YELLOW}<outdir>${RESET}" "${ORANGE}<matrix_path>${RESET}" "${GREEN}<matrix_sep>${RESET}" "${ORANGE}<metadata>${RESET}" "${GREEN}<metadata_sep>${RESET}" "${GREEN}<log2fc>${RESET}" "${GREEN}<fdr>${RESET}" "${GREEN}<ref_covar>${RESET}" "${GREEN}<target_covar>${RESET}" "${GREEN}<threads>${RESET}" "${GREEN}<quiet>${RESET}")

if [ "$#" -ne 12 ]; then
    echo -e "${WHITE}Usage: bash deseq2.sh ${USAGE_STR}${RESET}\n"
    echo -e "${YELLOW}A wrapper function for deseq2 for two groups only${RESET}\n"
    echo -e "${WHITE}Arguments:${RESET}"
    echo -e "${YELLOW}workdir        ${RESET} [io]  indicating the working folder"
    echo -e "${YELLOW}outdir         ${RESET} [out] indicating the folder where results will be written"
    echo -e "${ORANGE}matrix_path    ${RESET} [cp]  Path to the input expression matrix file (samples in columns, features/genes in rows)"
    echo -e "${GREEN}matrix_sep     ${RESET}       File separator (use \",\" or \";\" for CSV, \"\t\" ora \"tab\" for TSV) for matrix file"
    echo -e "${ORANGE}metadata       ${RESET} [cp]  A CSV or TSV file containing metadata for files in the input director"
    echo -e "${GREEN}metadata_sep   ${RESET}       File separator (use \",\" or \";\" for CSV, \"\t\" ora \"tab\" for TSV) for metadata file"
    echo -e "${GREEN}log2fc         ${RESET}       Log2 Fold Change absolute threshold for filtering differentially expressed genes (e.g., 1.0 for a 2-fold change)"
    echo -e "${GREEN}fdr            ${RESET}       False Discovery Rate threshold (adjusted p-value / padj) used to control for multiple testing significance (e.g., 0.05)."
    echo -e "${GREEN}ref_covar      ${RESET}       The reference or baseline level of the primary condition variable (e.g., control, untreated, wildtype), used as the denominator in the differential expression contrast matrix."
    echo -e "${GREEN}target_covar   ${RESET}       The target or experimental level of the primary condition variable (e.g., treated, knockout, mutant), evaluated against the reference baseline to calculate fold change values."
    echo -e "${GREEN}threads        ${RESET}       a number indicating the number of cores to be used from the application"
    echo -e "${GREEN}quiet          ${RESET}       Set to \"true\" to suppress tool processing messages, set to \"false\" to keep verbose logging enabled."
    exit 1
fi

# Parse positional arguments
workdir="${1}"
outdir="${2}"
matrix_path="${3}"
matrix_sep="${4}"
metadata="${5}"
metadata_sep="${6}"
log2fc="${7}"
fdr="${8}"
ref_covar="${9}"
target_covar="${10}"
threads="${11}"
quiet="${12}"

# --- Input validation ---
errors=()

if [ ! -d "${workdir}" ]; then
    errors+=("Directory not found: workdir = ${workdir}")
fi
if [ ! -d "${outdir}" ]; then
    errors+=("Directory not found: outdir = ${outdir}")
fi
if [ ! -f "${matrix_path}" ]; then
    errors+=("File not found: matrix_path = ${matrix_path}")
fi
if [ ! -f "${metadata}" ]; then
    errors+=("File not found: metadata = ${metadata}")
fi
if ! echo "${matrix_sep}" | grep -qE "^(,|;|\\t|tab)$"; then
    errors+=("Invalid value for matrix_sep: ${matrix_sep}. Allowed: [',', ';', '\\t', 'tab']")
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

# --- Bind files and service volumes ---
declare -A mounted_folders
_src_matrix_path="$(realpath "${matrix_path}")"
cp "${_src_matrix_path}" "${scratch_path}/"
docker_vals["matrix_path"]="/workDir/$(basename "${_src_matrix_path}")"

_src_metadata="$(realpath "${metadata}")"
cp "${_src_metadata}" "${scratch_path}/"
docker_vals["metadata"]="/workDir/$(basename "${_src_metadata}")"

docker_vals["matrix_sep"]="${matrix_sep}"
docker_vals["metadata_sep"]="${metadata_sep}"
docker_vals["log2fc"]="${log2fc}"
docker_vals["fdr"]="${fdr}"
docker_vals["ref_covar"]="${ref_covar}"
docker_vals["target_covar"]="${target_covar}"
docker_vals["threads"]="${threads}"
docker_vals["quiet"]="${quiet}"

mount_str="${mounts[*]}"
PARAM_NAMES=("matrix_sep" "metadata_sep" "log2fc" "fdr" "ref_covar" "target_covar" "threads" "quiet")
special_chars_re='[;&|()<>$`"'"'"'[:space:]]'
cmd="docker run --rm ${mount_str} ghcr.io/reproduciblebioinformatics/docker4seq-deseq2-v2:latest bash /home/start.sh <outdir> <matrix_path> <matrix_sep> <metadata> <metadata_sep> <log2fc> <fdr> <ref_covar> <target_covar> <threads> <quiet>"
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