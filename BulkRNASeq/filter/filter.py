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

    usage_str = ' '.join([f'\033[93m<workdir>{RESET}', f'\033[93m<outdir>{RESET}', f'\033[38;5;208m<de_full>{RESET}', f'\033[38;5;208m<raw_counts>{RESET}', f'\033[38;5;208m<norm_counts>{RESET}', f'\033[92m<log2fc>{RESET}', f'\033[92m<padj>{RESET}', f'\033[92m<threads>{RESET}', f'\033[92m<quiet>{RESET}'])

    if len(sys.argv) != 10:
        print(f'{WHITE}Usage: python filter.py {usage_str}{RESET}\n')
        print(f'{YELLOW}Description: A utility script that filters DESeq2 results (DE_FULL.txt) based on user-defined Log2 Fold-Change (LFC) and False Discovery Rate (FDR/padj) thresholds. It exports the statistically significant differential expression metrics (DE_Filtered.txt) and subsets both the raw (DE_counts.txt) and log2-normalized (DE_normalizedCounts.txt) expression matrices to retain only the features that passed the selection criteria{RESET}\n')
        print(f'{WHITE}Arguments:{RESET}')
        print(f'\033[93mworkdir        {RESET} [io]  indicating the working folder')
        print(f'\033[93moutdir         {RESET} [out] indicating the folder where results will be written')
        print(f'\033[38;5;208mde_full        {RESET} [cp]  The complete, unfiltered output from DESeq2 containing all tested genes with their respective statistical metrics, including base mean, log2 fold-changes (LFC), p-values, and adjusted p-values (FDR/padj)')
        print(f'\033[38;5;208mraw_counts     {RESET} [cp]  A filtered subset of the primary raw expression matrix, containing only the non-normalized integer read counts of genes that passed the user-defined statistical thresholds across all samples.')
        print(f'\033[38;5;208mnorm_counts    {RESET} [cp]  A filtered matrix containing library-size corrected and $\log_2$-transformed expression levels for statistically significant genes, ideal for downstream clustering, heatmaps, and PCA.')
        print(f'\033[92mlog2fc         {RESET}       Log2 Fold Change absolute threshold for filtering differentially expressed genes (e.g., 1.0 for a 2-fold change)')
        print(f'\033[92mpadj           {RESET}       The actual statistic calculated for each gene, which has been corrected for multiple testing (typically via the Benjamini-Hochberg procedure) to ensure that filtering by this value maintains the global FDR at the desired level.')
        print(f'\033[92mthreads        {RESET}       a number indicating the number of cores to be used from the application')
        print(f'\033[92mquiet          {RESET}       Set to \"true\" to suppress tool processing messages, set to \"false\" to keep verbose logging enabled.')
        sys.exit(1)

    # Parse positional arguments
    args = {}
    args['workdir'] = sys.argv[1]
    args['outdir'] = sys.argv[2]
    args['de_full'] = sys.argv[3]
    args['raw_counts'] = sys.argv[4]
    args['norm_counts'] = sys.argv[5]
    args['log2fc'] = sys.argv[6]
    args['padj'] = sys.argv[7]
    args['threads'] = sys.argv[8]
    args['quiet'] = sys.argv[9]

    # --- Input validation ---
    errors = []

    if not os.path.isdir(args['workdir']):
        errors.append(f'Directory not found: workdir = {args["workdir"]}"')
    if not os.path.isdir(args['outdir']):
        errors.append(f'Directory not found: outdir = {args["outdir"]}"')
    if not os.path.isfile(args['de_full']):
        errors.append(f'File not found: de_full = {args["de_full"]}"')
    if not os.path.isfile(args['raw_counts']):
        errors.append(f'File not found: raw_counts = {args["raw_counts"]}"')
    if not os.path.isfile(args['norm_counts']):
        errors.append(f'File not found: norm_counts = {args["norm_counts"]}"')
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
    _src_de_full = os.path.abspath(args['de_full'])
    shutil.copy(_src_de_full, scratch_path)
    docker_vals['de_full'] = f'/workDir/{os.path.basename(_src_de_full)}'

    _src_raw_counts = os.path.abspath(args['raw_counts'])
    shutil.copy(_src_raw_counts, scratch_path)
    docker_vals['raw_counts'] = f'/workDir/{os.path.basename(_src_raw_counts)}'

    _src_norm_counts = os.path.abspath(args['norm_counts'])
    shutil.copy(_src_norm_counts, scratch_path)
    docker_vals['norm_counts'] = f'/workDir/{os.path.basename(_src_norm_counts)}'

    docker_vals['log2fc'] = args['log2fc']
    docker_vals['padj'] = args['padj']
    docker_vals['threads'] = args['threads']
    docker_vals['quiet'] = args['quiet']

    # --- Assemble docker command ---
    cmd = ' ghcr.io/reproduciblebioinformatics/docker4seq-filter-v2:latest bash /home/start.sh <de_full> <raw_counts> <norm_counts> <outdir> <log2fc> <padj> <threads> <quiet>'
    mount_str = ' '.join(mounts)
    cmd = ' '.join(['docker run --rm', mount_str, ' ghcr.io/reproduciblebioinformatics/docker4seq-filter-v2:latest bash /home/start.sh <de_full> <raw_counts> <norm_counts> <outdir> <log2fc> <padj> <threads> <quiet>'])
    PARAM_NAMES = ['log2fc', 'padj', 'threads', 'quiet']
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