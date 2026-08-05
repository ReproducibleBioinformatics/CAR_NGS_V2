#!/usr/bin/env bash
set -euo pipefail

# ANSI color codes
RED='\033[91m'
WHITE='\033[97m'
YELLOW='\033[93m'
ORANGE='\033[38;5;208m'
GREEN='\033[92m'
RESET='\033[0m'

USAGE_STR=$(echo -e "${YELLOW}<workdir>${RESET}" "${YELLOW}<inputdir>${RESET}" "${YELLOW}<outdir>${RESET}" "${GREEN}<adapter5>${RESET}" "${GREEN}<adapter3>${RESET}" "${GREEN}<seq_type>${RESET}" "${ORANGE}<metadata>${RESET}" "${GREEN}<metadata_sep>${RESET}" "${GREEN}<threads>${RESET}" "${GREEN}<quiet>${RESET}")

if [ "$#" -ne 10 ]; then
    echo -e "${WHITE}Usage: bash skewer.sh ${USAGE_STR}${RESET}\n"
    echo -e "${YELLOW}This function executes the docker container skewer1 to remove sequencing adapters from RNAseq reads${RESET}\n"
    echo -e "${WHITE}Arguments:${RESET}"
    echo -e "${YELLOW}workdir        ${RESET} [io]  indicating the working folder"
    echo -e "${YELLOW}inputdir       ${RESET} [in]  indicating where gzip fastq files are located"
    echo -e "${YELLOW}outdir         ${RESET} [out] indicating the folder where results will be written"
    echo -e "${GREEN}adapter5       ${RESET}       character string indicating the fwd adapter"
    echo -e "${GREEN}adapter3       ${RESET}       character string indicating the rev adapter"
    echo -e "${GREEN}seq_type       ${RESET}       type of reads to be trimmed. Two options: \"se\" or \"pe\" respectively for single end and pair end sequencing."
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
adapter5="${4}"
adapter3="${5}"
seq_type="${6}"
metadata="${7}"
metadata_sep="${8}"
threads="${9}"
quiet="${10}"

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
if [ ! -f "${metadata}" ]; then
    errors+=("File not found: metadata = ${metadata}")
fi
if ! echo "${seq_type}" | grep -qE "^(pe|se)$"; then
    errors+=("Invalid value for seq_type: ${seq_type}. Allowed: ['pe', 'se']")
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
mounts+=("-v \"$(realpath "${inputdir}"):/data_fastq\"")
docker_vals["inputdir"]="/data_fastq"

# --- Bind files and service volumes ---
declare -A mounted_folders
_src_metadata="$(realpath "${metadata}")"
cp "${_src_metadata}" "${scratch_path}/"
docker_vals["metadata"]="/workDir/$(basename "${_src_metadata}")"

docker_vals["adapter5"]="${adapter5}"
docker_vals["adapter3"]="${adapter3}"
docker_vals["seq_type"]="${seq_type}"
docker_vals["metadata_sep"]="${metadata_sep}"
docker_vals["threads"]="${threads}"
docker_vals["quiet"]="${quiet}"

mount_str="${mounts[*]}"
PARAM_NAMES=("adapter5" "adapter3" "seq_type" "metadata_sep" "threads" "quiet")
special_chars_re='[;&|()<>$`"'"'"'[:space:]]'
cmd="docker run --rm ${mount_str} ghcr.io/reproduciblebioinformatics/docker4seq-skewer-v2:latest bash /home/start.sh <inputdir> <outdir> <adapter5> <adapter3> <seq_type> <metadata> <metadata_sep> <threads> <quiet>"
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