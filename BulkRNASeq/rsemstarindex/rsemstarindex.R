# ANSI color codes
RED    <- '\033[91m'
WHITE  <- '\033[97m'
YELLOW <- '\033[93m'
ORANGE <- '\033[38;5;208m'
GREEN  <- '\033[92m'
RESET  <- '\033[0m'

cat_col <- function(..., color = WHITE) {
  cat(color, ..., RESET, '\n', sep = '')
}

rsemstarindex <- function(workdir = NULL, outdir = NULL, fastafile = NULL, gtffile = NULL, filter = NULL, chrom_pattern = NULL, threads = NULL, quiet = NULL) {

  if (any(sapply(list(workdir, outdir, fastafile, gtffile, filter, chrom_pattern, threads, quiet), is.null))) {
    cat(WHITE, 'Usage: rsemstarindex(<workdir> <outdir> <fastafile> <gtffile> <filter> <chrom_pattern> <threads> <quiet>)', RESET, '\n\n', sep = '')
    cat(YELLOW, "This function executes the docker container rsem-star1 where RSEM and STAR are installed. The index is created using ENSEMBL genome fasta file.", RESET, "\n\n", sep = "")
    cat_col('Arguments:', color = WHITE)
    cat('\033[93mworkdir         [io]  indicating the working folder', RESET, '\n', sep = '')
    cat('\033[93moutdir          [out] indicating the scratch folder where docker container will be mounted.', RESET, '\n', sep = '')
    cat('\033[38;5;208mfastafile       [cp]  Contains the raw DNA sequence (chromosomes) of the reference genome, used by STAR as the blueprint for alignment', RESET, '\n', sep = '')
    cat('\033[38;5;208mgtffile         [cp]  Contains the gene annotations (coordinates of exons, introns, and transcripts), used by RSEM to quantify gene expression.', RESET, '\n', sep = '')
    cat('\033[92mfilter                Genome filtration strategy applied prior to indexing. Options: 'none' (no filtering), 'all' (removes long-name scaffolds and mitochondrial DNA), 'mito' (removes mitochondrial DNA only), 'chrom' (removes long-name scaffolds only)', RESET, '\n', sep = '')
    cat('\033[92mchrom_pattern         Optional regex to override the default chromosome-naming pattern used to identify main chromosomes (e.g., '^chr[0-9]+$'). Use 'null' to keep the default.', RESET, '\n', sep = '')
    cat('\033[92mthreads               a number indicating the number of cores to be used from the application', RESET, '\n', sep = '')
    cat('\033[92mquiet                 Set to \\"true\\" to suppress tool processing messages, set to \\"false\\" to keep verbose logging enabled.', RESET, '\n', sep = '')
    stop('Missing required arguments')
  }

  args <- list()
  args$workdir <- workdir
  args$outdir <- outdir
  args$fastafile <- fastafile
  args$gtffile <- gtffile
  args$filter <- filter
  args$chrom_pattern <- chrom_pattern
  args$threads <- threads
  args$quiet <- quiet

  # --- Input validation ---
  errors <- character(0)

  if (!dir.exists(args$workdir)) {
    errors <- c(errors, paste0('Directory not found: workdir = ', args$workdir))
  }
  if (!dir.exists(args$outdir)) {
    errors <- c(errors, paste0('Directory not found: outdir = ', args$outdir))
  }
  if (!file.exists(args$fastafile)) {
    errors <- c(errors, paste0('File not found: fastafile = ', args$fastafile))
  }
  if (!file.exists(args$gtffile)) {
    errors <- c(errors, paste0('File not found: gtffile = ', args$gtffile))
  }
  if (!args$filter %in% c("none", "all", "mito", "chrom")) {
    errors <- c(errors, paste0('Invalid value for filter: ', args$filter, '. Allowed: none, all, mito, chrom'))
  }
  if (!args$quiet %in% c("false", "true")) {
    errors <- c(errors, paste0('Invalid value for quiet: ', args$quiet, '. Allowed: false, true'))
  }

  if (length(errors) > 0) {
    for (e in errors) cat(RED, 'ERROR: ', RESET, WHITE, e, RESET, '\n', sep = '')
    stop('Input validation failed')
  }

  # --- Scratch directory setup ---
  n <- 1
  repeat {
    if (dir.exists(file.path(normalizePath(args$workdir), paste0('scratch', n))) || dir.exists(file.path(normalizePath(args$outdir), paste0('output', n)))) {
      n <- n + 1
    } else {
      break
    }
  }

  scratch_path <- file.path(normalizePath(args$workdir), paste0('scratch', n))
  dir.create(scratch_path, recursive = TRUE, showWarnings = FALSE)
  scratch_out_path <- file.path(normalizePath(args$outdir), paste0('output', n))
  dir.create(scratch_out_path, recursive = TRUE, showWarnings = FALSE)

  # --- Build docker volume mounts ---
  mounts      <- character(0)
  docker_vals <- list()
  service_idx <- 1

  mounts <- c(mounts, paste0('-v "', scratch_path, ':/workDir"'))
  docker_vals$workdir <- '/workDir'

  mounts <- c(mounts, paste0('-v "', scratch_out_path, ':/results"'))
  docker_vals$outdir <- '/results'

  # --- Bind files and service volumes ---
  mounted_folders <- list()

  src_fastafile <- normalizePath(args$fastafile)
  file.copy(src_fastafile, scratch_path)
  docker_vals$fastafile <- paste0('/workDir/', basename(src_fastafile))

  src_gtffile <- normalizePath(args$gtffile)
  file.copy(src_gtffile, scratch_path)
  docker_vals$gtffile <- paste0('/workDir/', basename(src_gtffile))

  docker_vals$filter <- args$filter
  docker_vals$chrom_pattern <- args$chrom_pattern
  docker_vals$threads <- args$threads
  docker_vals$quiet <- args$quiet

  # --- Assemble docker command ---
  mount_str <- paste(mounts, collapse = ' ')
  cmd <- paste('docker run --rm', mount_str, 'ghcr.io/reproduciblebioinformatics/docker4seq-rsemstarindex-v2:latest bash /home/start.sh <outdir> <fastafile> <gtffile> <filter> <chrom_pattern> <threads> <quiet>')
  placeholders <- regmatches(cmd, gregexpr('<[^>]+>', cmd))[[1]]
  for (ph in placeholders) {
    key <- gsub('<|>', '', ph)
    val <- docker_vals[[key]]
    if (!is.null(val)) {
      if (grepl('[;&|()<>$\\`"\'\\s]', val, perl = TRUE)) val <- paste0('"', gsub('"', '\\"', val, fixed = TRUE), '"')
      cmd <- gsub(ph, val, cmd, fixed = TRUE)
    }
  }
  cat('\n', YELLOW, 'Running:\n', RESET, WHITE, cmd, RESET, '\n\n', sep = '')
  log_path <- file.path(scratch_path, 'output_log.txt')
  cat(YELLOW, 'Log: ', RESET, WHITE, log_path, RESET, '\n\n', sep = '')

  con <- file(log_path, open = 'w')
  p   <- pipe(paste(cmd, '2>&1'), open = 'r')
  while (length(line <- readLines(p, n = 1, warn = FALSE)) > 0) {
    cat(line, '\n', sep = '')
    writeLines(line, con)
  }
  ret <- close(p)
  close(con)

  if (ret == 0) {
    cat('\n', GREEN, 'Done. Log saved to: ', log_path, RESET, '\n', sep = '')
  } else {
    cat('\n', RED, 'Docker exited with code ', ret, '. See log: ', log_path, RESET, '\n', sep = '')
  }
  return(invisible(ret))
}