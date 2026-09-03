import os
import sys
import subprocess
from datetime import datetime
from pathlib import Path

SCRIPT_NAME = "test-cellranger_count"
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

# Configurations and directory paths
workdir = "workdir"
out_dir = "results/"
fastqs = "../testdata/fastq"

# Parameter setup (matching cellranger_count.bala positional order)
chemistry = "auto"         # Options: auto, threeprime, fiveprime, SC3Pv1, SC3Pv2, SC3Pv3, SC5P-PE, SC5P-R2, ARC-v1
expect_cells = "NULL"      # Positive integer or "NULL" for default automatic estimation
force_cells = "NULL"       # Positive integer or "NULL" for default automatic detection
nosecondary = "false"      # "true" to disable PCA/clustering, "false" or "NULL" to keep enabled
r1length = "NULL"          # Read 1 hard-trimming length or "NULL"
r2length = "NULL"          # Read 2 hard-trimming length or "NULL"
lanes = "NULL"             # Specific lane numbers (e.g. "1" or "1,2") or "NULL"
max_memory = "16"          # Memory limit in GB
threads = "8"              # CPU threads allocation
save_bam = "true"

# Ensure working directories exist
os.makedirs(workdir, exist_ok=True)
os.makedirs(out_dir, exist_ok=True)


# Individuazione dell'ultima cartella di output generata da cellrangerindex
latest_index_dir = get_latest_output_dir("../cellranger_index/results")

# Controllo di esistenza obbligatorio
if not latest_index_dir or not os.path.exists(latest_index_dir):
    raise FileNotFoundError("Errore fatale: Nessuna run precedente trovata in '../cellranger_index/results'. "
                            "Eseguire prima il modulo cellranger_index.")

# Recupera la cartella dell'indice genomico creata dentro l'output
# (cellranger mkref crea una sottocartella con il nome del genoma dentro la cartella di output)
subdirs = [os.path.join(latest_index_dir, d) for d in os.listdir(latest_index_dir) 
           if os.path.isdir(os.path.join(latest_index_dir, d))]

if not subdirs:
    raise FileNotFoundError(f"Errore fatale: Nessuna cartella di riferimento genomico trovata dentro '{latest_index_dir}'.")

transcriptome = subdirs[0]  # Seleziona la cartella dell'indice generata da cellranger mkref



log_test("Executing cellranger_count pipeline via Python wrapper...")

# Execution of cellranger_count.py wrapper with ordered arguments
cmd = [
    sys.executable,
    "cellranger_count.py",
    workdir,
    out_dir,
    transcriptome,
    fastqs,
    chemistry,
    expect_cells,
    force_cells,
    nosecondary,
    r1length,
    r2length,
    lanes,
    save_bam,
    max_memory,
    threads,
    quiet
]

subprocess.run(cmd, check=True)