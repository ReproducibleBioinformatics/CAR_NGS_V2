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

    usage_str = ' '.join([f'\033[93m<workdir>{RESET}', f'\033[93m<outdir>{RESET}', f'\033[38;5;208m<fastafile>{RESET}', f'\033[38;5;208m<gtffile>{RESET}', f'\033[92m<gene_biotype>{RESET}', f'\033[92m<max_memory>{RESET}', f'\033[92m<threads>{RESET}', f'\033[92m<quiet>{RESET}'])

    if len(sys.argv) != 9:
        print(f'{WHITE}Usage: python cellranger_index.py {usage_str}{RESET}\n')
        print(f'{YELLOW}runs Illumina bcl2fastq2 to demultiplex a sequencing run: it converts raw BCL base-call files from an Illumina run folder into per-sample, gzip-compressed FASTQ files according to the sample indexes listed in a SampleSheet.csv, and writes the resulting FASTQ files together with the bcl2fastq execution log to the specified output directory.{RESET}\n')
        print(f'{WHITE}Arguments:{RESET}')
        print(f'\033[93mworkdir        {RESET} [io]  indicating the working folder')
        print(f'\033[93moutdir         {RESET} [out] indicating the folder where results will be written')
        print(f'\033[38;5;208mfastafile      {RESET} [cp]  Contains the raw DNA sequence (chromosomes) of the reference genome, used by STAR as the blueprint for alignment')
        print(f'\033[38;5;208mgtffile        {RESET} [cp]  Contains the gene annotations (coordinates of exons, introns, and transcripts), used by RSEM to quantify gene expression.')
        print(f'\033[92mgene_biotype   {RESET}       gene biotype')
        print(f'\033[92mmax_memory     {RESET}       Maximum amount of memory (RAM) that Cell Ranger is allowed to use.')
        print(f'\033[92mthreads        {RESET}       a number indicating the number of cores to be used from the application')
        print(f'\033[92mquiet          {RESET}       Set to \"true\" to suppress tool processing messages, set to \"false\" to keep verbose logging enabled.')
        sys.exit(1)

    # Parse positional arguments
    args = {}
    args['workdir'] = sys.argv[1]
    args['outdir'] = sys.argv[2]
    args['fastafile'] = sys.argv[3]
    args['gtffile'] = sys.argv[4]
    args['gene_biotype'] = sys.argv[5]
    args['max_memory'] = sys.argv[6]
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
    if args['gene_biotype'] not in ['all', 'protein_coding', 'unitary_pseudogene', 'unprocessed_pseudogene', 'processed_pseudogene', 'transcribed_unprocessed_pseudogene', 'processed_transcript', 'antisense', 'transcribed_unitary_pseudogene', 'polymorphic_pseudogene', 'lincRNA', 'sense_intronic', 'transcribed_processed_pseudogene', 'sense_overlapping', 'IG_V_pseudogene', 'pseudogene', 'TR_V_gene', '3prime_overlapping_ncRNA', 'IG_V_gene', 'bidirectional_promoter_lncRNA', 'snRNA', 'miRNA', 'misc_RNA', 'snoRNA', 'rRNA', 'IG_C_gene', 'IG_J_gene', 'TR_J_gene', 'TR_C_gene', 'TR_V_pseudogene', 'TR_J_pseudogene', 'IG_D_gene', 'ribozyme', 'IG_C_pseudogene', 'TR_D_gene', 'TEC', 'IG_J_pseudogene', 'scRNA', 'scaRNA', 'vaultRNA', 'sRNA', 'macro_lncRNA', 'non_coding', 'IG_pseudogene']:
        errors.append(f"""Invalid value for gene_biotype: {args["gene_biotype"]}. Allowed: ['all', 'protein_coding', 'unitary_pseudogene', 'unprocessed_pseudogene', 'processed_pseudogene', 'transcribed_unprocessed_pseudogene', 'processed_transcript', 'antisense', 'transcribed_unitary_pseudogene', 'polymorphic_pseudogene', 'lincRNA', 'sense_intronic', 'transcribed_processed_pseudogene', 'sense_overlapping', 'IG_V_pseudogene', 'pseudogene', 'TR_V_gene', '3prime_overlapping_ncRNA', 'IG_V_gene', 'bidirectional_promoter_lncRNA', 'snRNA', 'miRNA', 'misc_RNA', 'snoRNA', 'rRNA', 'IG_C_gene', 'IG_J_gene', 'TR_J_gene', 'TR_C_gene', 'TR_V_pseudogene', 'TR_J_pseudogene', 'IG_D_gene', 'ribozyme', 'IG_C_pseudogene', 'TR_D_gene', 'TEC', 'IG_J_pseudogene', 'scRNA', 'scaRNA', 'vaultRNA', 'sRNA', 'macro_lncRNA', 'non_coding', 'IG_pseudogene']""")
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

    docker_vals['gene_biotype'] = args['gene_biotype']
    docker_vals['max_memory'] = args['max_memory']
    docker_vals['threads'] = args['threads']
    docker_vals['quiet'] = args['quiet']

    # --- Assemble docker command ---
    cmd = ' cellranger_index bash /home/start.sh <outdir> <fastafile> <gtffile> <gene_biotype> <max_memory> <threads> <quiet>'
    mount_str = ' '.join(mounts)
    cmd = ' '.join(['docker run --rm', mount_str, ' cellranger_index bash /home/start.sh <outdir> <fastafile> <gtffile> <gene_biotype> <max_memory> <threads> <quiet>'])
    PARAM_NAMES = ['gene_biotype', 'max_memory', 'threads', 'quiet']
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