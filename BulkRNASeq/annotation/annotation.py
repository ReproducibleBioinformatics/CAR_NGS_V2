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

    usage_str = ' '.join([f'\033[93m<workdir>{RESET}', f'\033[93m<inputdir>{RESET}', f'\033[93m<outdir>{RESET}', f'\033[38;5;208m<annotation_file>{RESET}', f'\033[92m<gene_biotype>{RESET}', f'\033[38;5;208m<metadata>{RESET}', f'\033[92m<metadata_sep>{RESET}', f'\033[92m<threads>{RESET}', f'\033[92m<quiet>{RESET}'])

    if len(sys.argv) != 10:
        print(f'{WHITE}Usage: python annotation.py {usage_str}{RESET}\n')
        print(f'{YELLOW}This Docker image annotates RSEM genes.results output files with gene symbols/names retrieved from a matching GTF/GFF3 annotation file, batch-processing all samples in an input directory and writing the annotated TSV files to a specified output directory.{RESET}\n')
        print(f'{WHITE}Arguments:{RESET}')
        print(f'\033[93mworkdir        {RESET} [io]  indicating the working folder')
        print(f'\033[93minputdir       {RESET} [in]  indicating where genes.results files are located')
        print(f'\033[93moutdir         {RESET} [out] indicating the folder where results will be written')
        print(f'\033[38;5;208mannotation_file{RESET} [cp]  gene annotation file (GTF or GFF3 format) used to map gene IDs to gene names/symbols.')
        print(f'\033[92mgene_biotype   {RESET}       gene biotype')
        print(f'\033[38;5;208mmetadata       {RESET} [cp]  A CSV or TSV file containing metadata for files in the input director')
        print(f'\033[92mmetadata_sep   {RESET}       File separator (use \",\" or \";\" for CSV, \"\t\" ora \"tab\" for TSV)')
        print(f'\033[92mthreads        {RESET}       a number indicating the number of cores to be used from the application')
        print(f'\033[92mquiet          {RESET}       Set to \"true\" to suppress tool processing messages, set to \"false\" to keep verbose logging enabled.')
        sys.exit(1)

    # Parse positional arguments
    args = {}
    args['workdir'] = sys.argv[1]
    args['inputdir'] = sys.argv[2]
    args['outdir'] = sys.argv[3]
    args['annotation_file'] = sys.argv[4]
    args['gene_biotype'] = sys.argv[5]
    args['metadata'] = sys.argv[6]
    args['metadata_sep'] = sys.argv[7]
    args['threads'] = sys.argv[8]
    args['quiet'] = sys.argv[9]

    # --- Input validation ---
    errors = []

    if not os.path.isdir(args['workdir']):
        errors.append(f'Directory not found: workdir = {args["workdir"]}"')
    if not os.path.isdir(args['inputdir']):
        errors.append(f'Directory not found: inputdir = {args["inputdir"]}"')
    if not os.path.isdir(args['outdir']):
        errors.append(f'Directory not found: outdir = {args["outdir"]}"')
    if not os.path.isfile(args['annotation_file']):
        errors.append(f'File not found: annotation_file = {args["annotation_file"]}"')
    if not os.path.isfile(args['metadata']):
        errors.append(f'File not found: metadata = {args["metadata"]}"')
    if args['gene_biotype'] not in ['protein_coding', 'unitary_pseudogene', 'unprocessed_pseudogene', 'processed_pseudogene', 'transcribed_unprocessed_pseudogene', 'processed_transcript', 'antisense', 'transcribed_unitary_pseudogene', 'polymorphic_pseudogene', 'lincRNA', 'sense_intronic', 'transcribed_processed_pseudogene', 'sense_overlapping', 'IG_V_pseudogene', 'pseudogene', 'TR_V_gene', '3prime_overlapping_ncRNA', 'IG_V_gene', 'bidirectional_promoter_lncRNA', 'snRNA', 'miRNA', 'misc_RNA', 'snoRNA', 'rRNA', 'IG_C_gene', 'IG_J_gene', 'TR_J_gene', 'TR_C_gene', 'TR_V_pseudogene', 'TR_J_pseudogene', 'IG_D_gene', 'ribozyme', 'IG_C_pseudogene', 'TR_D_gene', 'TEC', 'IG_J_pseudogene', 'scRNA', 'scaRNA', 'vaultRNA', 'sRNA', 'macro_lncRNA', 'non_coding', 'IG_pseudogene']:
        errors.append(f"""Invalid value for gene_biotype: {args["gene_biotype"]}. Allowed: ['protein_coding', 'unitary_pseudogene', 'unprocessed_pseudogene', 'processed_pseudogene', 'transcribed_unprocessed_pseudogene', 'processed_transcript', 'antisense', 'transcribed_unitary_pseudogene', 'polymorphic_pseudogene', 'lincRNA', 'sense_intronic', 'transcribed_processed_pseudogene', 'sense_overlapping', 'IG_V_pseudogene', 'pseudogene', 'TR_V_gene', '3prime_overlapping_ncRNA', 'IG_V_gene', 'bidirectional_promoter_lncRNA', 'snRNA', 'miRNA', 'misc_RNA', 'snoRNA', 'rRNA', 'IG_C_gene', 'IG_J_gene', 'TR_J_gene', 'TR_C_gene', 'TR_V_pseudogene', 'TR_J_pseudogene', 'IG_D_gene', 'ribozyme', 'IG_C_pseudogene', 'TR_D_gene', 'TEC', 'IG_J_pseudogene', 'scRNA', 'scaRNA', 'vaultRNA', 'sRNA', 'macro_lncRNA', 'non_coding', 'IG_pseudogene']""")
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

    # inputdir: read-write directory [in]
    mounts.append(f'-v "{os.path.abspath(args["inputdir"])}:/data_results"')
    docker_vals['inputdir'] = '/data_results'

    # --- Bind files and service volumes ---
    mounted_folders = {}
    _src_annotation_file = os.path.abspath(args['annotation_file'])
    shutil.copy(_src_annotation_file, scratch_path)
    docker_vals['annotation_file'] = f'/workDir/{os.path.basename(_src_annotation_file)}'

    _src_metadata = os.path.abspath(args['metadata'])
    shutil.copy(_src_metadata, scratch_path)
    docker_vals['metadata'] = f'/workDir/{os.path.basename(_src_metadata)}'

    docker_vals['gene_biotype'] = args['gene_biotype']
    docker_vals['metadata_sep'] = args['metadata_sep']
    docker_vals['threads'] = args['threads']
    docker_vals['quiet'] = args['quiet']

    # --- Assemble docker command ---
    cmd = ' ghcr.io/reproduciblebioinformatics/docker4seq-annotation-v2:latest bash /home/start.sh <workdir> <inputdir> <outdir> <annotation_file> <gene_biotype> <metadata> <metadata_sep> <threads> <quiet>'
    mount_str = ' '.join(mounts)
    cmd = ' '.join(['docker run --rm', mount_str, ' ghcr.io/reproduciblebioinformatics/docker4seq-annotation-v2:latest bash /home/start.sh <workdir> <inputdir> <outdir> <annotation_file> <gene_biotype> <metadata> <metadata_sep> <threads> <quiet>'])
    PARAM_NAMES = ['gene_biotype', 'metadata_sep', 'threads', 'quiet']
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