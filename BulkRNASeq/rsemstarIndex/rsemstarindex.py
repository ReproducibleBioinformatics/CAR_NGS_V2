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

    usage_str = ' '.join([f'\033[93m<workdir>{RESET}', f'\033[93m<outdir>{RESET}', f'\033[38;5;208m<fastafile>{RESET}', f'\033[38;5;208m<gtffile>{RESET}', f'\033[92m<filter>{RESET}', f'\033[92m<chrom_pattern>{RESET}', f'\033[92m<threads>{RESET}', f'\033[92m<quiet>{RESET}'])

    if len(sys.argv) != 9:
        print(f'{WHITE}Usage: python rsemstarindex.py {usage_str}{RESET}\n')
        print(f'{YELLOW}This function executes the docker container rsem-star1 where RSEM and STAR are installed. The index is created using ENSEMBL genome fasta file.{RESET}\n')
        print(f'{WHITE}Arguments:{RESET}')
        print(f'\033[93mworkdir        {RESET} [io]  indicating the working folder')
        print(f'\033[93moutdir         {RESET} [out] indicating the scratch folder where docker container will be mounted')
        print(f'\033[38;5;208mfastafile      {RESET} [cp]  Contains the raw DNA sequence (chromosomes) of the reference genome, used by STAR as the blueprint for alignment')
        print(f'\033[38;5;208mgtffile        {RESET} [cp]  Contains the gene annotations (coordinates of exons, introns, and transcripts), used by RSEM to quantify gene expression.')
        print(f'\033[92mfilter         {RESET}       Genome filtration strategy applied prior to indexing. Options: \'none\' (no filtering), \'all\' (removes long-name scaffolds and mitochondrial DNA), \'mito\' (removes mitochondrial DNA only), \'chrom\' (removes long-name scaffolds only)')
        print(f'\033[92mchrom_pattern  {RESET}       Optional regex to override the default chromosome-naming pattern used to identify main chromosomes (e.g., \'^chr[0-9]+$\'). Use \'null\' to keep the default.')
        print(f'\033[92mthreads        {RESET}       a number indicating the number of cores to be used from the application')
        print(f'\033[92mquiet          {RESET}       Set to \"true\" to suppress tool processing messages, set to \"false\" to keep verbose logging enabled.')
        sys.exit(1)

    # Parse positional arguments
    args = {}
    args['workdir'] = sys.argv[1]
    args['outdir'] = sys.argv[2]
    args['fastafile'] = sys.argv[3]
    args['gtffile'] = sys.argv[4]
    args['filter'] = sys.argv[5]
    args['chrom_pattern'] = sys.argv[6]
    args['threads'] = sys.argv[7]
    args['quiet'] = sys.argv[8]

    # --- Input validation ---
    errors = []

    if not os.path.isdir(args['workdir']):
        errors.append(f'Directory not found: workdir = {args["workdir"]}"')
    if not os.path.isdir(args['outdir']):
        errors.append(f'Directory not found: outdir = {args["outdir"]}"')
    if not os.path.isfile(args['fastafile']):
        errors.append(f'File not found: fastafile = {args["fastafile"]}"')
    if not os.path.isfile(args['gtffile']):
        errors.append(f'File not found: gtffile = {args["gtffile"]}"')
    if args['filter'] not in ['none', 'all', 'mito', 'chrom']:
        errors.append(f"""Invalid value for filter: {args["filter"]}. Allowed: ['none', 'all', 'mito', 'chrom']""")
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
    _src_fastafile = os.path.abspath(args['fastafile'])
    shutil.copy(_src_fastafile, scratch_path)
    docker_vals['fastafile'] = f'/workDir/{os.path.basename(_src_fastafile)}'

    _src_gtffile = os.path.abspath(args['gtffile'])
    shutil.copy(_src_gtffile, scratch_path)
    docker_vals['gtffile'] = f'/workDir/{os.path.basename(_src_gtffile)}'

    docker_vals['filter'] = args['filter']
    docker_vals['chrom_pattern'] = args['chrom_pattern']
    docker_vals['threads'] = args['threads']
    docker_vals['quiet'] = args['quiet']

    # --- Assemble docker command ---
    cmd = ' ghcr.io/reproduciblebioinformatics/docker4seq-rsemstarIndex-v2:latest bash /home/start.sh <outdir> <fastafile> <gtffile> <filter> <threads> <chrom_pattern> <quiet>'
    mount_str = ' '.join(mounts)
    cmd = ' '.join(['docker run --rm', mount_str, ' ghcr.io/reproduciblebioinformatics/docker4seq-rsemstarIndex-v2:latest bash /home/start.sh <outdir> <fastafile> <gtffile> <filter> <threads> <chrom_pattern> <quiet>'])
    PARAM_NAMES = ['filter', 'chrom_pattern', 'threads', 'quiet']
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