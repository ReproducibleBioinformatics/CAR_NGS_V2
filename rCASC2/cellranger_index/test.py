import os
import re
import sys
import subprocess
from datetime import datetime
from pathlib import Path

SCRIPT_NAME = "test-cellranger_index"
PINK = "\033[1;35m"
NC = "\033[0m"

quiet = "false"
QUIET = quiet.lower() == "true"

def log_test(message):
    if QUIET:
        return
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"{PINK}[{timestamp}] [{SCRIPT_NAME} PROCESS] {message}{NC}")

def get_latest_output_dir(base_dir):
    base_path = Path(base_dir)
    if not base_path.is_dir():
        return ""
    
    max_num = -1
    latest_dir = ""
    
    for entry in base_path.glob("output*"):
        if entry.is_dir():
            folder_name = entry.name
            num_str = folder_name.replace("output", "")
            if num_str.isdigit():
                num = int(num_str)
                if num > max_num:
                    max_num = num
                    latest_dir = str(entry)
                    
    return latest_dir

# Configurazioni e percorsi
workdir = "workdir"
results = "results/"
gtffile = "../testdata/reference/Homo_sapiens.GRCh37.75.21.gtf"
fastafile = "../testdata/reference/chr21.fa"
biotype = "protein_coding"
max_memory = "17"
threads = "8"
lenient = "true"

# Creazione cartelle di lavoro
os.makedirs(workdir, exist_ok=True)
os.makedirs(results, exist_ok=True)

# Individuazione cartella di output più recente e file di metadata
input_dir = get_latest_output_dir("../rsemstar/results")
metadata = os.path.join(input_dir, "sampleMetaData_rsemstar.csv") if input_dir else ""

log_test("Executing cellranger_index pipeline via Python wrapper...")

# Esecuzione del wrapper demultiplexing.py
cmd = [
    sys.executable,  # Usa l'interprete Python attualmente attivo nel sistema
    "cellranger_index.py",
    workdir,
    results,
    fastafile,
    gtffile,    
    biotype,
    max_memory,
    threads,
    quiet
]

subprocess.run(cmd, check=True)