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

    usage_str = ' '.join([f'\033[93m<workdir>{RESET}', f'\033[93m<outdir>{RESET}', f'\033[93m<transcriptome>{RESET}', f'\033[93m<fastqs>{RESET}', f'\033[92m<chemistry>{RESET}', f'\033[92m<expect_cells>{RESET}', f'\033[92m<force_cells>{RESET}', f'\033[92m<nosecondary>{RESET}', f'\033[92m<r1length>{RESET}', f'\033[92m<r2length>{RESET}', f'\033[92m<lanes>{RESET}', f'\033[92m<save_bam>{RESET}', f'\033[92m<max_memory>{RESET}', f'\033[92m<threads>{RESET}', f'\033[92m<quiet>{RESET}'])

    if len(sys.argv) != 16:
        print(f'{WHITE}Usage: python cellranger_count.py {usage_str}{RESET}\n')
        print(f'{YELLOW}aligns 10x Genomics single-cell FASTQ reads to a reference transcriptome, filters barcodes and UMIs, and generates gene-expression count matrices per cell{RESET}\n')
        print(f'{WHITE}Arguments:{RESET}')
        print(f'\033[93mworkdir        {RESET} [io]  indicating the working folder')
        print(f'\033[93moutdir         {RESET} [out] indicating the folder where results will be written')
        print(f'\033[93mtranscriptome  {RESET} [in]  Specifies the path to the Cell Ranger-compatible reference genome and transcriptome directory (mounted at /transcr).')
        print(f'\033[93mfastqs         {RESET} [in]  Specifies the input directory path containing the raw FASTQ files (mounted at /data)..')
        print(f'\033[92mchemistry      {RESET}       Specifies the Single Cell library assay configuration.')
        print(f'\033[92mexpect_cells   {RESET}       Sets the expected number of recovered cells to guide the cell-calling algorithm. Passing NULL leaves the default Cell Ranger automatic estimation.')
        print(f'\033[92mforce_cells    {RESET}       Forces the pipeline to detect a fixed number of cells, overriding the automatic cell detection algorithm. Passing NULL leaves the default automatic detection.')
        print(f'\033[92mnosecondary    {RESET}       Disables secondary analysis execution, such as PCA, t-SNE, UMAP dimensionality reduction, and automated cell clustering. If set to FALSE or NULL, default secondary analysis is executed.')
        print(f'\033[92mr1length       {RESET}       Hard-trims Read 1 sequences to a fixed number of bases prior to alignment. Passing NULL leaves the default behavior of using the full read length without trimming.')
        print(f'\033[92mr2length       {RESET}       Hard-trims Read 2 sequences to a fixed number of bases prior to alignment. Passing NULL leaves the default behavior of using the full read length without trimming.')
        print(f'\033[92mlanes          {RESET}       Restricts analysis to specific flowcell lane numbers. Passing NULL processes all available lanes in the input directory.')
        print(f'\033[92msave_bam       {RESET}       boolean indicating whether the genome and transcriptome bam files should be kept in outDir')
        print(f'\033[92mmax_memory     {RESET}       Maximum amount of memory (RAM) that Cell Ranger is allowed to use.')
        print(f'\033[92mthreads        {RESET}       a number indicating the number of cores to be used from the application')
        print(f'\033[92mquiet          {RESET}       Set to \"true\" to suppress tool processing messages, set to \"false\" to keep verbose logging enabled.')
        sys.exit(1)

    # Parse positional arguments
    args = {}
    args['workdir'] = sys.argv[1]
    args['outdir'] = sys.argv[2]
    args['transcriptome'] = sys.argv[3]
    args['fastqs'] = sys.argv[4]
    args['chemistry'] = sys.argv[5]
    args['expect_cells'] = sys.argv[6]
    args['force_cells'] = sys.argv[7]
    args['nosecondary'] = sys.argv[8]
    args['r1length'] = sys.argv[9]
    args['r2length'] = sys.argv[10]
    args['lanes'] = sys.argv[11]
    args['save_bam'] = sys.argv[12]
    args['max_memory'] = sys.argv[13]
    args['threads'] = sys.argv[14]
    args['quiet'] = sys.argv[15]

    # --- Input validation ---
    errors = []

    if not os.path.isdir(args['workdir']):
        errors.append(f'Directory not found: workdir = {args["workdir"]}"')
    if not os.path.isdir(args['outdir']):
        errors.append(f'Directory not found: outdir = {args["outdir"]}"')
    if not os.path.isdir(args['transcriptome']):
        errors.append(f'Directory not found: transcriptome = {args["transcriptome"]}"')
    if not os.path.isdir(args['fastqs']):
        errors.append(f'Directory not found: fastqs = {args["fastqs"]}"')
    if args['chemistry'] not in ['auto', 'threeprime', 'fiveprime', 'SC3Pv1', 'SC3Pv2', 'SC3Pv3', 'SC5P-PE', 'SC5P-R2', 'ARC-v1']:
        errors.append(f"""Invalid value for chemistry: {args["chemistry"]}. Allowed: ['auto', 'threeprime', 'fiveprime', 'SC3Pv1', 'SC3Pv2', 'SC3Pv3', 'SC5P-PE', 'SC5P-R2', 'ARC-v1']""")
    if args['save_bam'] not in ['true', 'false']:
        errors.append(f"""Invalid value for save_bam: {args["save_bam"]}. Allowed: ['true', 'false']""")
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

    # transcriptome: read-write directory [in]
    mounts.append(f'-v "{os.path.abspath(args["transcriptome"])}:/transcr"')
    docker_vals['transcriptome'] = '/transcr'

    # fastqs: read-write directory [in]
    mounts.append(f'-v "{os.path.abspath(args["fastqs"])}:/data"')
    docker_vals['fastqs'] = '/data'

    # --- Bind files and service volumes ---
    mounted_folders = {}
    docker_vals['chemistry'] = args['chemistry']
    docker_vals['expect_cells'] = args['expect_cells']
    docker_vals['force_cells'] = args['force_cells']
    docker_vals['nosecondary'] = args['nosecondary']
    docker_vals['r1length'] = args['r1length']
    docker_vals['r2length'] = args['r2length']
    docker_vals['lanes'] = args['lanes']
    docker_vals['save_bam'] = args['save_bam']
    docker_vals['max_memory'] = args['max_memory']
    docker_vals['threads'] = args['threads']
    docker_vals['quiet'] = args['quiet']

    # --- Assemble docker command ---
    cmd = ' cellranger_count bash /home/start.sh <outdir> <transcriptome> <fastqs> <chemistry> <expect_cells> <force_cells> <nosecondary> <r1length> <r2length> <lanes> <save_bam> <max_memory> <threads> <quiet>'
    mount_str = ' '.join(mounts)
    cmd = ' '.join(['docker run --rm', mount_str, ' cellranger_count bash /home/start.sh <outdir> <transcriptome> <fastqs> <chemistry> <expect_cells> <force_cells> <nosecondary> <r1length> <r2length> <lanes> <save_bam> <max_memory> <threads> <quiet>'])
    PARAM_NAMES = ['chemistry', 'expect_cells', 'force_cells', 'nosecondary', 'r1length', 'r2length', 'lanes', 'save_bam', 'max_memory', 'threads', 'quiet']
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