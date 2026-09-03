import os
import sys
import subprocess
from datetime import datetime
from pathlib import Path

SCRIPT_NAME = "test-matrix_reshaper"
PINK = "\033[1;35m"
NC = "\033[0m"

quiet = "false"
QUIET = quiet.lower() == "true"

def log_test(message):
    if QUIET:
        return
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"{PINK}[{timestamp}] [{SCRIPT_NAME} PROCESS] {message}{NC}")

workdir = "workdir"
out_dir = "results/"
input_file = "../testdata/matrices/filtered_feature_bc_matrix.h5"
output_file = "converted_matrix.csv"
separator = ","         # Opzioni: ',', ';', '\t', 'tab'
max_memory = "16"       # RAM massima allocata in GB
threads = "8"           # Numero di core CPU allocati
os.makedirs(workdir, exist_ok=True)
os.makedirs(out_dir, exist_ok=True)
log_test("Executing matrix_reshaper pipeline via Python wrapper...")
cmd = [
    sys.executable,
    "matrix_reshaper.py",
    out_dir,
    input_file,
    output_file,
    separator,
    max_memory,
    threads,
    quiet
]

subprocess.run(cmd, check=True)