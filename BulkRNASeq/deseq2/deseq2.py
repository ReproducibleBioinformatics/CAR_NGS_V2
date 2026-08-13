import os, sys, shutil, subprocess, re

# ANSI color codes
RED    = '\033[91m'
WHITE  = '\033[97m'
YELLOW = '\033[93m'
ORANGE = '\033[38;5;208m'
GREEN  = '\033[92m'
RESET  = '\033[0m'


def main():
    if os.name == 'nt':
        os.system('color')

    usage_str = ' '.join([f'\033[93m<workdir>{RESET}', f'\033[93m<outdir>{RESET}', f'\033[38;5;208m<matrix_path>{RESET}', f'\033[92m<matrix_sep>{RESET}', f'\033[38;5;208m<metadata>{RESET}', f'\033[92m<metadata_sep>{RESET}', f'\033[92m<log2fc>{RESET}', f'\033[92m<fdr>{RESET}', f'\033[92m<ref_covar>{RESET}', f'\033[92m<target_covar>{RESET}', f'\033[92m<threads>{RESET}', f'\033[92m<quiet>{RESET}'])

    if len(sys.argv) != 13:
        print(f'{WHITE}Usage: python deseq2.py {usage_str}{RESET}\n')
        print(f'{YELLOW}A wrapper function for deseq2 for two groups only{RESET}\n')
        print(f'{WHITE}Arguments:{RESET}')
        print(f'\033[93mworkdir        {RESET} [io]  indicating the working folder')
        print(f'\033[93moutdir         {RESET} [out] indicating the folder where results will be written')
        print(f'\033[38;5;208mmatrix_path    {RESET} [cp]  Path to the input expression matrix file (samples in columns, features/genes in rows)')
        print(f'\033[92mmatrix_sep     {RESET}       File separator (use \",\" or \";\" for CSV, \"\t\" ora \"tab\" for TSV) for matrix file')
        print(f'\033[38;5;208mmetadata       {RESET} [cp]  A CSV or TSV file containing metadata for files in the input director')
        print(f'\033[92mmetadata_sep   {RESET}       File separator (use \",\" or \";\" for CSV, \"\t\" ora \"tab\" for TSV) for metadata file')
        print(f'\033[92mlog2fc         {RESET}       Log2 Fold Change absolute threshold for filtering differentially expressed genes (e.g., 1.0 for a 2-fold change)')
        print(f'\033[92mfdr            {RESET}       False Discovery Rate threshold (adjusted p-value / padj) used to control for multiple testing significance (e.g., 0.05).')
        print(f'\033[92mref_covar      {RESET}       The reference or baseline level of the primary condition variable (e.g., control, untreated, wildtype), used as the denominator in the differential expression contrast matrix.')
        print(f'\033[92mtarget_covar   {RESET}       The target or experimental level of the primary condition variable (e.g., treated, knockout, mutant), evaluated against the reference baseline to calculate fold change values.')
        print(f'\033[92mthreads        {RESET}       a number indicating the number of cores to be used from the application')
        print(f'\033[92mquiet          {RESET}       Set to \"true\" to suppress tool processing messages, set to \"false\" to keep verbose logging enabled.')
        sys.exit(1)

    # Parse positional arguments
    args = {}
    args['workdir'] = sys.argv[1]
    args['outdir'] = sys.argv[2]
    args['matrix_path'] = sys.argv[3]
    args['matrix_sep'] = sys.argv[4]
    args['metadata'] = sys.argv[5]
    args['metadata_sep'] = sys.argv[6]
    args['log2fc'] = sys.argv[7]
    args['fdr'] = sys.argv[8]
    args['ref_covar'] = sys.argv[9]
    args['target_covar'] = sys.argv[10]
    args['threads'] = sys.argv[11]
    args['quiet'] = sys.argv[12]

    # --- Input validation ---
    errors = []

    if not os.path.isdir(args['workdir']):
        errors.append(f'Directory not found: workdir = {args["workdir"]}"')
    if not os.path.isdir(args['outdir']):
        errors.append(f'Directory not found: outdir = {args["outdir"]}"')
    if not os.path.isfile(args['matrix_path']):
        errors.append(f'File not found: matrix_path = {args["matrix_path"]}"')
    if not os.path.isfile(args['metadata']):
        errors.append(f'File not found: metadata = {args["metadata"]}"')
    if args['matrix_sep'] not in [',', ';', '\\t', 'tab']:
        errors.append(f"""Invalid value for matrix_sep: {args["matrix_sep"]}. Allowed: [',', ';', '\\t', 'tab']""")
    if args['metadata_sep'] not in [',', ';', '\\t', 'tab']:
        errors.append(f"""Invalid value for metadata_sep: {args["metadata_sep"]}. Allowed: [',', ';', '\\t', 'tab']""")
    if args['quiet'] not in ['false', 'true']:
        errors.append(f"""Invalid value for quiet: {args["quiet"]}. Allowed: ['false', 'true']""")

    if errors:
        for e in errors:
            print(f'{RED}ERROR:{RESET} {WHITE}{e}{RESET}')
        sys.exit(1)

    # --- Scratch directory setup ---
    n = 1
    while True:
        if os.path.exists(os.path.join(os.path.abspath(args['workdir']), f'scratch{n}')) or os.path.exists(os.path.join(os.path.abspath(args['outdir']), f'output{n}')):
            n += 1
        else:
            break

    scratch_path = os.path.join(os.path.abspath(args['workdir']), f'scratch{n}')
    os.makedirs(scratch_path, exist_ok=True)
    scratch_out_path = os.path.join(os.path.abspath(args['outdir']), f'output{n}')
    os.makedirs(scratch_out_path, exist_ok=True)

    # --- Build docker volume mounts ---
    mounts = []
    docker_vals = {}   # placeholder -> docker-internal path
    service_idx = 1    # counter for read-only service mounts

    mounts.append(f'-v "{scratch_path}:/workDir"')
    docker_vals['workdir'] = '/workDir'

    mounts.append(f'-v "{scratch_out_path}:/results"')
    docker_vals['outdir'] = '/results'

    # --- Bind files and service volumes ---
    mounted_folders = {}
    _src_matrix_path = os.path.abspath(args['matrix_path'])
    shutil.copy(_src_matrix_path, scratch_path)
    docker_vals['matrix_path'] = f'/workDir/{os.path.basename(_src_matrix_path)}'

    _src_metadata = os.path.abspath(args['metadata'])
    shutil.copy(_src_metadata, scratch_path)
    docker_vals['metadata'] = f'/workDir/{os.path.basename(_src_metadata)}'

    docker_vals['matrix_sep'] = args['matrix_sep']
    docker_vals['metadata_sep'] = args['metadata_sep']
    docker_vals['log2fc'] = args['log2fc']
    docker_vals['fdr'] = args['fdr']
    docker_vals['ref_covar'] = args['ref_covar']
    docker_vals['target_covar'] = args['target_covar']
    docker_vals['threads'] = args['threads']
    docker_vals['quiet'] = args['quiet']

    # --- Assemble docker command ---
    cmd = ' ghcr.io/reproduciblebioinformatics/docker4seq-deseq2-v2:latest bash /home/start.sh <outdir> <matrix_path> <matrix_sep> <metadata> <metadata_sep> <log2fc> <fdr> <ref_covar> <target_covar> <threads> <quiet>'
    mount_str = ' '.join(mounts)
    cmd = ' '.join(['docker run --rm', mount_str, ' ghcr.io/reproduciblebioinformatics/docker4seq-deseq2-v2:latest bash /home/start.sh <outdir> <matrix_path> <matrix_sep> <metadata> <metadata_sep> <log2fc> <fdr> <ref_covar> <target_covar> <threads> <quiet>'])
    PARAM_NAMES = ['matrix_sep', 'metadata_sep', 'log2fc', 'fdr', 'ref_covar', 'target_covar', 'threads', 'quiet']
    def replace_placeholder(match):
        key = match.group(1)
        val = str(docker_vals.get(key, match.group(0)))
        if key in PARAM_NAMES:
            if re.search(r'[;&|()<>$`"\'\s]', val):
                escaped_val = val.replace('"', '\\"')
                return f'"{escaped_val}"'
        return val

    cmd = re.sub(r'<([^>]+)>', replace_placeholder, cmd)

    print(f'\n{YELLOW}Running:{RESET}\n{WHITE}{cmd}{RESET}\n')

    log_path = os.path.join(scratch_path, 'output_log.txt')
    print(f'{YELLOW}Log:{RESET} {WHITE}{log_path}{RESET}\n')
    with open(log_path, 'w', encoding='utf-8') as log_f:
        p = subprocess.Popen(
            cmd, shell=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True
        )
        for line in p.stdout:
            sys.stdout.write(line)
            log_f.write(line)
        p.wait()

    if p.returncode == 0:
        print(f'\n{GREEN}Done. Log saved to: {log_path}{RESET}')
    else:
        print(f'\n{RED}Docker exited with code {p.returncode}. See log: {log_path}{RESET}')
    sys.exit(p.returncode)


if __name__ == '__main__':
    main()