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

    usage_str = ' '.join([f'\033[93m<workdir>{RESET}', f'\033[93m<outdir>{RESET}', f'\033[38;5;208m<input_file>{RESET}', f'\033[92m<output_file>{RESET}', f'\033[92m<separator>{RESET}', f'\033[92m<max_memory>{RESET}', f'\033[92m<threads>{RESET}', f'\033[92m<quiet>{RESET}'])

    if len(sys.argv) != 9:
        print(f'{WHITE}Usage: python matrix_reshaper.py {usage_str}{RESET}\n')
        print(f'{YELLOW}Converts single-cell expression matrices between sparse formats (.h5, .mtx) and dense formats (.csv, .tsv, .txt), auto-detecting direction from input/output file extensions.{RESET}\n')
        print(f'{WHITE}Arguments:{RESET}')
        print(f'\033[93mworkdir        {RESET} [io]  indicating the working folder')
        print(f'\033[93moutdir         {RESET} [out] indicating the folder where results will be written')
        print(f'\033[38;5;208minput_file     {RESET} [cp]  Path to the input expression matrix file (.h5, .mtx, .csv, .tsv, .txt). For .mtx files, associated barcode and feature tsv files are automatically read from the same folder.')
        print(f'\033[92moutput_file    {RESET}       Path for the output expression matrix file (.csv, .tsv, .txt, or .mtx). When writing a .mtx file, associated barcodes.tsv and features.tsv files are automatically generated in the same target folder.')
        print(f'\033[92mseparator      {RESET}       File separator (use \",\" or \";\" for CSV, \"\t\" ora \"tab\" for TSV)')
        print(f'\033[92mmax_memory     {RESET}       Maximum amount of memory (RAM) that Cell Ranger is allowed to use.')
        print(f'\033[92mthreads        {RESET}       a number indicating the number of cores to be used from the application')
        print(f'\033[92mquiet          {RESET}       Set to \"true\" to suppress tool processing messages, set to \"false\" to keep verbose logging enabled.')
        sys.exit(1)

    # Parse positional arguments
    args = {}
    args['workdir'] = sys.argv[1]
    args['outdir'] = sys.argv[2]
    args['input_file'] = sys.argv[3]
    args['output_file'] = sys.argv[4]
    args['separator'] = sys.argv[5]
    args['max_memory'] = sys.argv[6]
    args['threads'] = sys.argv[7]
    args['quiet'] = sys.argv[8]

    # --- Input validation ---
    errors = []

    if not os.path.isdir(args['workdir']):
        errors.append(f'Directory not found: workdir = {args["workdir"]}"')
    if not os.path.isdir(args['outdir']):
        errors.append(f'Directory not found: outdir = {args["outdir"]}"')
    if not os.path.isfile(args['input_file']):
        errors.append(f'File not found: input_file = {args["input_file"]}"')
    if args['separator'] not in [',', ';', '\\t', 'tab']:
        errors.append(f"""Invalid value for separator: {args["separator"]}. Allowed: [',', ';', '\\t', 'tab']""")
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
    _src_input_file = os.path.abspath(args['input_file'])
    shutil.copy(_src_input_file, scratch_path)
    docker_vals['input_file'] = f'/workDir/{os.path.basename(_src_input_file)}'

    docker_vals['output_file'] = args['output_file']
    docker_vals['separator'] = args['separator']
    docker_vals['max_memory'] = args['max_memory']
    docker_vals['threads'] = args['threads']
    docker_vals['quiet'] = args['quiet']

    # --- Assemble docker command ---
    cmd = ' pippo bash /home/start.sh <outdir> <input_file> <output_file> <separator> <max_memory> <threads> <quiet>'
    mount_str = ' '.join(mounts)
    cmd = ' '.join(['docker run --rm', mount_str, ' pippo bash /home/start.sh <outdir> <input_file> <output_file> <separator> <max_memory> <threads> <quiet>'])
    PARAM_NAMES = ['output_file', 'separator', 'max_memory', 'threads', 'quiet']
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