import os, re, csv, sys
from datetime import datetime

# ------- Color Definitions ------- #
NC, CYAN, YELLOW, GREEN, RED = '\033[0m', '\033[0;36m', '\033[1;33m', '\033[0;32m', '\033[0;31m'

# ------- Logging Utility Functions ------- #
def log_info(msg): print(f"{CYAN}[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] [sample-generator INFO]    {msg}{NC}")
def log_step(msg): print(f"{YELLOW}[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] [sample-generator PROCESS] {msg}{NC}")
def log_success(msg): print(f"{GREEN}[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] [sample-generator SUCCESS] {msg}{NC}")
def log_error(msg): print(f"{RED}[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] [sample-generator ERROR]   {msg}{NC}")
def log_sep(char='=', color=CYAN): print(f"{color}{char * 100}{NC}")

def show_usage():
    script_name = os.path.basename(sys.argv[0])
    log_sep("-", YELLOW)
    print(f"{YELLOW}Usage:{NC}\n  python {script_name} <INPUT_DIR> [OUTPUT_PATH]\n")
    print(f"{YELLOW}Arguments:{NC}\n  {CYAN}INPUT_DIR{NC}      Base directory containing FASTQ files (Required)")
    print(f"  {CYAN}OUTPUT_PATH{NC}    Optional target folder or target CSV file path (Default: ./sampleMetaData.csv)\n")
    print(f"{YELLOW}Options:{NC}\n  {CYAN}-h, --help{NC}     Show this help message and exit")
    log_sep("-", YELLOW)

def is_fastq_file(filename):
    """Check if file matches valid FASTQ extensions (plain or gzipped)."""
    return filename.lower().endswith(('.fastq', '.fq', '.fastq.gz', '.fq.gz'))

def parse_output_target(out_arg):
    """Resolve output directory and filename based on user input."""
    if os.path.isdir(out_arg) or out_arg.endswith((os.sep, '/')):
        return os.path.abspath(out_arg), 'sampleMetaData.csv'
    out_dir, out_file = os.path.split(out_arg)
    return os.path.abspath(out_dir) if out_dir else os.getcwd(), out_file or 'sampleMetaData.csv'

def generate_sample_sheet():
    # ------- CLI Arguments Validation ------- #
    if len(sys.argv) < 2 or sys.argv[1] in ['-h', '--help']:
        show_usage()
        sys.exit(0)

    input_dir = os.path.abspath(sys.argv[1])
    out_dir, out_filename = parse_output_target(sys.argv[2]) if len(sys.argv) > 2 else (os.getcwd(), 'sampleMetaData.csv')
    output_filepath = os.path.join(out_dir, out_filename)

    log_sep()
    log_info("Initializing Sample Sheet Generator Pipeline")
    log_step("Validating input/output paths and parameters...")

    if not os.path.isdir(input_dir):
        log_error(f"INPUT_DIR ({input_dir}) does not exist. Execution aborted.")
        sys.exit(3)

    os.makedirs(out_dir, exist_ok=True)

    # ------- Scan FASTQ Files recursively ------- #
    fastq_files = []
    try:
        for root, _, files in os.walk(input_dir):
            for file in files:
                if is_fastq_file(file):
                    fastq_files.append((root, file))
    except Exception as e:
        log_error(f"Failed to read input directory: {e}")
        sys.exit(1)

    fastq_files.sort(key=lambda x: os.path.join(x[0], x[1]))
    if not fastq_files:
        log_error(f"No FASTQ files found in target directory: {input_dir}")
        sys.exit(1)

    # ------- Process FASTQ Files and Map Metadata ------- #
    pattern = re.compile(r'^([a-zA-Z]+)(\d+)(?:_([^.]+))?')
    csv_data, global_sample_counter, sample_mapping = [], 0, {}
    log_step(f"Processing {len(fastq_files)} FASTQ files from: {input_dir}")

    for root, filename in fastq_files:
        abs_root = os.path.abspath(root)
        rel_path = os.path.relpath(abs_root, input_dir)
        # ------- Force POSIX slashes for Docker/Linux compatibility ------- #
        sample_folder = "" if rel_path == "." else rel_path.replace(os.sep, '/')
        
        match = pattern.match(filename)
        if match:
            covariate, local_num, _ = match.groups()
            sample_key = (covariate, local_num)
            if sample_key not in sample_mapping:
                global_sample_counter += 1
                sample_mapping[sample_key] = global_sample_counter
            sample_number = sample_mapping[sample_key]
            vis_name = f"{covariate}_{local_num}"
        else:
            base_name = filename
            for ext in ['.gz', '.fastq', '.fq']:
                if base_name.lower().endswith(ext): base_name = base_name[:-len(ext)]
            covariate = "".join(re.findall(r'^[a-zA-Z]+', base_name)) or "unknown"
            sample_key = (base_name,)
            if sample_key not in sample_mapping:
                global_sample_counter += 1
                sample_mapping[sample_key] = global_sample_counter
            sample_number = sample_mapping[sample_key]
            vis_name = base_name

        csv_data.append({
            'SampleName': filename, 'SampleFolder': sample_folder,
            'sampleNumber': sample_number, 'Batch': "NA",
            'Covariate': covariate, 'VisName': vis_name
        })

    # ------- Generate CSV Metadata Output File ------- #
    headers = ['SampleName', 'SampleFolder', 'sampleNumber', 'Batch', 'Covariate', 'VisName']
    try:
        with open(output_filepath, mode='w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=headers, delimiter=',')
            writer.writeheader()
            writer.writerows(csv_data)
        log_sep()
        log_success(f"Execution completed successfully. File generated at: '{output_filepath}'")
        log_success("Pipeline Terminated Successfully.")
    except Exception as e:
        log_error(f"Error writing metadata CSV file: {e}")
        log_error("Pipeline Terminated with Errors.")
        sys.exit(1)

if __name__ == '__main__':
    generate_sample_sheet()