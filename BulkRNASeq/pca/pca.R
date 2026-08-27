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

pca <- function(workdir = NULL, outdir = NULL, matrix_path = NULL, matrix_sep = NULL, metadata = NULL, metadata_sep = NULL, pca_type = NULL, log_transform = NULL, remove_zero_var = NULL, blind = NULL, threads = NULL, quiet = NULL) {

  if (any(sapply(list(workdir, outdir, matrix_path, matrix_sep, metadata, metadata_sep, pca_type, log_transform, remove_zero_var, blind, threads, quiet), is.null))) {
    cat(WHITE, 'Usage: pca(<workdir> <outdir> <matrix_path> <matrix_sep> <metadata> <metadata_sep> <pca_type> <log_transform> <remove_zero_var> <blind> <threads> <quiet>)', RESET, '\n\n', sep = '')
    cat(YELLOW, "Generate PCA graph", RESET, "\n\n", sep = "")
    cat_col('Arguments:', color = WHITE)
    cat('\033[93mworkdir         [io]  indicating the working folder', RESET, '\n', sep = '')
    cat('\033[93moutdir          [out] indicating the folder where results will be written', RESET, '\n', sep = '')
    cat('\033[38;5;208mmatrix_path     [cp]  Path to the input expression matrix file (samples in columns, features/genes in rows)', RESET, '\n', sep = '')
    cat('\033[92mmatrix_sep            File separator (use \\",\\" or \\";\\" for CSV, \\"\t\\" ora \\"tab\\" for TSV)', RESET, '\n', sep = '')
    cat('\033[38;5;208mmetadata        [cp]  A CSV or TSV file containing metadata for files in the input director', RESET, '\n', sep = '')
    cat('\033[92mmetadata_sep          File separator (use \\",\\" or \\";\\" for CSV, \\"\t\\" ora \\"tab\\" for TSV)', RESET, '\n', sep = '')
    cat('\033[92mpca_type              Specifies the normalization and transformation method to apply to the expression matrix prior to Principal Component Analysis (PCA). Must be one of \\"Standard\\" (no advanced normalization), \\"deseq\\" (blind variance-stabilizing transformation), or \\"deseqNormalized\\" (design-aware, covariate-adjusted transformation).', RESET, '\n', sep = '')
    cat('\033[92mlog_transform         Applies a log_2(x + 1) transformation to the expression matrix before PCA to reduce skewness and stabilize variance. If FALSE, input values are processed as-is.', RESET, '\n', sep = '')
    cat('\033[92mremove_zero_var       Filters out non-informative features (genes with zero variance across samples) prior to PCA to avoid numerical errors in prcomp. If FALSE, all features are retained.', RESET, '\n', sep = '')
    cat('\033[92mblind                 Whether the variance-stabilizing transformation should ignore (TRUE) or account for (FALSE) the experimental design.', RESET, '\n', sep = '')
    cat('\033[92mthreads               a number indicating the number of cores to be used from the application', RESET, '\n', sep = '')
    cat('\033[92mquiet                 Set to \\"true\\" to suppress tool processing messages, set to \\"false\\" to keep verbose logging enabled.', RESET, '\n', sep = '')
    stop('Missing required arguments')
  }

  args <- list()
  args$workdir <- workdir
  args$outdir <- outdir
  args$matrix_path <- matrix_path
  args$matrix_sep <- matrix_sep
  args$metadata <- metadata
  args$metadata_sep <- metadata_sep
  args$pca_type <- pca_type
  args$log_transform <- log_transform
  args$remove_zero_var <- remove_zero_var
  args$blind <- blind
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
  if (!file.exists(args$matrix_path)) {
    errors <- c(errors, paste0('File not found: matrix_path = ', args$matrix_path))
  }
  if (!file.exists(args$metadata)) {
    errors <- c(errors, paste0('File not found: metadata = ', args$metadata))
  }
  if (!args$matrix_sep %in% c(",", ";", "\t", "tab")) {
    errors <- c(errors, paste0('Invalid value for matrix_sep: ', args$matrix_sep, '. Allowed: ,, ;, \t, tab'))
  }
  if (!args$metadata_sep %in% c(",", ";", "\t", "tab")) {
    errors <- c(errors, paste0('Invalid value for metadata_sep: ', args$metadata_sep, '. Allowed: ,, ;, \t, tab'))
  }
  if (!args$pca_type %in% c("Standard", "deseq", "deseqNormalized")) {
    errors <- c(errors, paste0('Invalid value for pca_type: ', args$pca_type, '. Allowed: Standard, deseq, deseqNormalized'))
  }
  if (!args$log_transform %in% c("true", "false")) {
    errors <- c(errors, paste0('Invalid value for log_transform: ', args$log_transform, '. Allowed: true, false'))
  }
  if (!args$remove_zero_var %in% c("true", "false")) {
    errors <- c(errors, paste0('Invalid value for remove_zero_var: ', args$remove_zero_var, '. Allowed: true, false'))
  }
  if (!args$blind %in% c("true", "false")) {
    errors <- c(errors, paste0('Invalid value for blind: ', args$blind, '. Allowed: true, false'))
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

  src_matrix_path <- normalizePath(args$matrix_path)
  file.copy(src_matrix_path, scratch_path)
  docker_vals$matrix_path <- paste0('/workDir/', basename(src_matrix_path))

  src_metadata <- normalizePath(args$metadata)
  file.copy(src_metadata, scratch_path)
  docker_vals$metadata <- paste0('/workDir/', basename(src_metadata))

  docker_vals$matrix_sep <- args$matrix_sep
  docker_vals$metadata_sep <- args$metadata_sep
  docker_vals$pca_type <- args$pca_type
  docker_vals$log_transform <- args$log_transform
  docker_vals$remove_zero_var <- args$remove_zero_var
  docker_vals$blind <- args$blind
  docker_vals$threads <- args$threads
  docker_vals$quiet <- args$quiet

  # --- Assemble docker command ---
  mount_str <- paste(mounts, collapse = ' ')
  cmd <- paste('docker run --rm', mount_str, 'ghcr.io/reproduciblebioinformatics/docker4seq-pca-v2:latest bash /home/start.sh <outdir> <matrix_path> <matrix_sep> <metadata> <metadata_sep> <pca_type> <log_transform> <remove_zero_var> <blind> <threads> <quiet>')
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