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

qc_report <- function(workdir = NULL, inputdir = NULL, outdir = NULL, metadata = NULL, metadata_sep = NULL, threads = NULL, quiet = NULL) {

  if (any(sapply(list(workdir, inputdir, outdir, metadata, metadata_sep, threads, quiet), is.null))) {
    cat(WHITE, 'Usage: qc_report(<workdir> <inputdir> <outdir> <metadata> <metadata_sep> <threads> <quiet>)', RESET, '\n\n', sep = '')
    cat(YELLOW, "This function runs FastQC on each FASTQ file listed in the sample metadata file (matched via the SampleName column, optionally located under a SampleFolder subdirectory), then aggregates all results into a single MultiQC report. Output files are named <SampleFolder_>SampleName_fastqc.html/.zip.", RESET, "\n\n", sep = "")
    cat_col('Arguments:', color = WHITE)
    cat('\033[93mworkdir         [io]  indicating the working folder', RESET, '\n', sep = '')
    cat('\033[93minputdir        [in]  indicating the folder where input data(fastq) are located', RESET, '\n', sep = '')
    cat('\033[93moutdir          [out] indicating the folder where results will be written', RESET, '\n', sep = '')
    cat('\033[38;5;208mmetadata        [cp]  A CSV or TSV file containing metadata for files in the input director', RESET, '\n', sep = '')
    cat('\033[92mmetadata_sep          File separator (use \\",\\" or \\";\\" for CSV, \\"\t\\" ora \\"tab\\" for TSV)', RESET, '\n', sep = '')
    cat('\033[92mthreads               a number indicating the number of cores to be used from the application', RESET, '\n', sep = '')
    cat('\033[92mquiet                 Set to \\"true\\" to suppress tool processing messages, set to \\"false\\" to keep verbose logging enabled.', RESET, '\n', sep = '')
    stop('Missing required arguments')
  }

  args <- list()
  args$workdir <- workdir
  args$inputdir <- inputdir
  args$outdir <- outdir
  args$metadata <- metadata
  args$metadata_sep <- metadata_sep
  args$threads <- threads
  args$quiet <- quiet

  # --- Input validation ---
  errors <- character(0)

  if (!dir.exists(args$workdir)) {
    errors <- c(errors, paste0('Directory not found: workdir = ', args$workdir))
  }
  if (!dir.exists(args$inputdir)) {
    errors <- c(errors, paste0('Directory not found: inputdir = ', args$inputdir))
  }
  if (!dir.exists(args$outdir)) {
    errors <- c(errors, paste0('Directory not found: outdir = ', args$outdir))
  }
  if (!file.exists(args$metadata)) {
    errors <- c(errors, paste0('File not found: metadata = ', args$metadata))
  }
  if (!args$metadata_sep %in% c(",", ";", "\t", "tab")) {
    errors <- c(errors, paste0('Invalid value for metadata_sep: ', args$metadata_sep, '. Allowed: ,, ;, \t, tab'))
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

  # inputdir: read-write directory [in]
  mounts <- c(mounts, paste0('-v "', normalizePath(args$inputdir), ':/data_fastq"'))
  docker_vals$inputdir <- '/data_fastq'

  # --- Bind files and service volumes ---
  mounted_folders <- list()

  src_metadata <- normalizePath(args$metadata)
  file.copy(src_metadata, scratch_path)
  docker_vals$metadata <- paste0('/workDir/', basename(src_metadata))

  docker_vals$metadata_sep <- args$metadata_sep
  docker_vals$threads <- args$threads
  docker_vals$quiet <- args$quiet

  # --- Assemble docker command ---
  mount_str <- paste(mounts, collapse = ' ')
  cmd <- paste('docker run --rm', mount_str, 'ghcr.io/reproduciblebioinformatics/docker4seq-qc_report-v2:latest bash /home/start.sh <inputdir> <outdir> <metadata> <metadata_sep> <threads> <quiet>')
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