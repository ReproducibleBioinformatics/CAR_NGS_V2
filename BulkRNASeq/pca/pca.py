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

    usage_str = ' '.join([f'\033[93m<workdir>{RESET}', f'\033[93m<outdir>{RESET}', f'\033[38;5;208m<matrix_path>{RESET}', f'\033[92m<matrix_sep>{RESET}', f'\033[38;5;208m<metadata>{RESET}', f'\033[92m<metadata_sep>{RESET}', f'\033[92m<pca_type>{RESET}', f'\033[92m<log_transform>{RESET}', f'\033[92m<remove_zero_var>{RESET}', f'\033[92m<blind>{RESET}', f'\033[92m<threads>{RESET}', f'\033[92m<quiet>{RESET}'])

    if len(sys.argv) != 13:
        print(f'{WHITE}Usage: python pca.py {usage_str}{RESET}\n')
        print(f'{YELLOW}Generate PCA graph{RESET}\n')
        print(f'{WHITE}Arguments:{RESET}')
        print(f'\033[93mworkdir        {RESET} [io]  indicating the working folder')
        print(f'\033[93moutdir         {RESET} [out] indicating the folder where results will be written')
        print(f'\033[38;5;208mmatrix_path    {RESET} [cp]  Path to the input expression matrix file (samples in columns, features/genes in rows)')
        print(f'\033[92mmatrix_sep     {RESET}       File separator (use \",\" or \";\" for CSV, \"\t\" ora \"tab\" for TSV)')
        print(f'\033[38;5;208mmetadata       {RESET} [cp]  A CSV or TSV file containing metadata for files in the input director')
        print(f'\033[92mmetadata_sep   {RESET}       File separator (use \",\" or \";\" for CSV, \"\t\" ora \"tab\" for TSV)')
        print(f'\033[92mpca_type       {RESET}       Specifies the normalization and transformation method to apply to the expression matrix prior to Principal Component Analysis (PCA). Must be one of \"Standard\" (no advanced normalization), \"deseq\" (blind variance-stabilizing transformation), or \"deseqNormalized\" (design-aware, covariate-adjusted transformation).')
        print(f'\033[92mlog_transform  {RESET}       Applies a log_2(x + 1) transformation to the expression matrix before PCA to reduce skewness and stabilize variance. If FALSE, input values are processed as-is.')
        print(f'\033[92mremove_zero_var{RESET}       Filters out non-informative features (genes with zero variance across samples) prior to PCA to avoid numerical errors in prcomp. If FALSE, all features are retained.')
        print(f'\033[92mblind          {RESET}       Whether the variance-stabilizing transformation should ignore (TRUE) or account for (FALSE) the experimental design.')
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
    args['pca_type'] = sys.argv[7]
    args['log_transform'] = sys.argv[8]
    args['remove_zero_var'] = sys.argv[9]
    args['blind'] = sys.argv[10]
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
    if args['pca_type'] not in ['Standard', 'deseq', 'deseqNormalized']:
        errors.append(f"""Invalid value for pca_type: {args["pca_type"]}. Allowed: ['Standard', 'deseq', 'deseqNormalized']""")
    if args['log_transform'] not in ['true', 'false']:
        errors.append(f"""Invalid value for log_transform: {args["log_transform"]}. Allowed: ['true', 'false']""")
    if args['remove_zero_var'] not in ['true', 'false']:
        errors.append(f"""Invalid value for remove_zero_var: {args["remove_zero_var"]}. Allowed: ['true', 'false']""")
    if args['blind'] not in ['true', 'false']:
        errors.append(f"""Invalid value for blind: {args["blind"]}. Allowed: ['true', 'false']""")
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
    docker_vals['pca_type'] = args['pca_type']
    docker_vals['log_transform'] = args['log_transform']
    docker_vals['remove_zero_var'] = args['remove_zero_var']
    docker_vals['blind'] = args['blind']
    docker_vals['threads'] = args['threads']
    docker_vals['quiet'] = args['quiet']

    # --- Assemble docker command ---
    cmd = ' ghcr.io/reproduciblebioinformatics/docker4seq-pca-v2:latest bash /home/start.sh <outdir> <matrix_path> <matrix_sep> <metadata> <metadata_sep> <pca_type> <log_transform> <remove_zero_var> <blind> <threads> <quiet>'
    mount_str = ' '.join(mounts)
    cmd = ' '.join(['docker run --rm', mount_str, ' ghcr.io/reproduciblebioinformatics/docker4seq-pca-v2:latest bash /home/start.sh <outdir> <matrix_path> <matrix_sep> <metadata> <metadata_sep> <pca_type> <log_transform> <remove_zero_var> <blind> <threads> <quiet>'])
    PARAM_NAMES = ['matrix_sep', 'metadata_sep', 'pca_type', 'log_transform', 'remove_zero_var', 'blind', 'threads', 'quiet']
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