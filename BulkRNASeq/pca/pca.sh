#!/usr/bin/env bash
set -euo pipefail

# ANSI color codes
RED='\033[91m'
WHITE='\033[97m'
YELLOW='\033[93m'
ORANGE='\033[38;5;208m'
GREEN='\033[92m'
RESET='\033[0m'

USAGE_STR=$(echo -e "${YELLOW}<workdir>${RESET}" "${YELLOW}<outdir>${RESET}" "${ORANGE}<matrix_path>${RESET}" "${GREEN}<matrix_sep>${RESET}" "${ORANGE}<metadata>${RESET}" "${GREEN}<metadata_sep>${RESET}" "${GREEN}<pca_type>${RESET}" "${GREEN}<log_transform>${RESET}" "${GREEN}<remove_zero_var>${RESET}" "${GREEN}<threads>${RESET}" "${GREEN}<quiet>${RESET}")

if [ "$#" -ne 11 ]; then
    echo -e "${WHITE}Usage: bash pca.sh ${USAGE_STR}${RESET}\n"
    echo -e "${YELLOW}Generate PCA graph${RESET}\n"
    echo -e "${WHITE}Arguments:${RESET}"
    echo -e "${YELLOW}workdir        ${RESET} [io]  indicating the working folder"
    echo -e "${YELLOW}outdir         ${RESET} [out] indicating the folder where results will be written"
    echo -e "${ORANGE}matrix_path    ${RESET} [cp]  Path to the input expression matrix file (samples in columns, features/genes in rows)"
    echo -e "${GREEN}matrix_sep     ${RESET}       File separator (use \",\" or \";\" for CSV, \"\t\" ora \"tab\" for TSV)"
    echo -e "${ORANGE}metadata       ${RESET} [cp]  A CSV or TSV file containing metadata for files in the input director"
    echo -e "${GREEN}metadata_sep   ${RESET}       File separator (use \",\" or \";\" for CSV, \"\t\" ora \"tab\" for TSV)"
    echo -e "${GREEN}pca_type       ${RESET}       Specifies the normalization and transformation method to apply to the expression matrix prior to Principal Component Analysis (PCA). Must be one of \"Standard\" (no advanced normalization), \"deseq\" (blind variance-stabilizing transformation), or \"deseqNormalized\" (design-aware, covariate-adjusted transformation)."
    echo -e "${GREEN}log_transform  ${RESET}       Applies a log_2(x + 1) transformation to the expression matrix before PCA to reduce skewness and stabilize variance. If FALSE, input values are processed as-is."
    echo -e "${GREEN}remove_zero_var${RESET}       Filters out non-informative features (genes with zero variance across samples) prior to PCA to avoid numerical errors in prcomp. If FALSE, all features are retained."
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
pca_type="${7}"
log_transform="${8}"
remove_zero_var="${9}"
threads="${10}"
quiet="${11}"

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
if ! echo "${pca_type}" | grep -qE "^(Standard|deseq|deseqNormalized)$"; then
    errors+=("Invalid value for pca_type: ${pca_type}. Allowed: ['Standard', 'deseq', 'deseqNormalized']")
fi
if ! echo "${log_transform}" | grep -qE "^(true|false)$"; then
    errors+=("Invalid value for log_transform: ${log_transform}. Allowed: ['true', 'false']")
fi
if ! echo "${remove_zero_var}" | grep -qE "^(true|false)$"; then
    errors+=("Invalid value for remove_zero_var: ${remove_zero_var}. Allowed: ['true', 'false']")
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
docker_vals["pca_type"]="${pca_type}"
docker_vals["log_transform"]="${log_transform}"
docker_vals["remove_zero_var"]="${remove_zero_var}"
docker_vals["threads"]="${threads}"
docker_vals["quiet"]="${quiet}"

mount_str="${mounts[*]}"
PARAM_NAMES=("matrix_sep" "metadata_sep" "pca_type" "log_transform" "remove_zero_var" "threads" "quiet")
special_chars_re='[;&|()<>$`"'"'"'[:space:]]'
cmd="docker run --rm ${mount_str} ghcr.io/reproduciblebioinformatics/docker4seq-pca-v2:latest bash /home/start.sh <outdir> <matrix_path> <matrix_sep> <metadata> <metadata_sep> <pca_type> <log_transform> <remove_zero_var> <threads> <quiet>"
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