#!/usr/bin/env Rscript

# ==============================================================================
# CANONICAL WRAPPER for R PCA Plotting pipeline script.
# ==============================================================================
SCRIPT_NAME <- "plot_pca.R"

CYAN <- "\033[0;36m"; YELLOW <- "\033[1;33m"; ORANGE <- "\033[0;33m"; GREEN <- "\033[0;32m"; RED <- "\033[0;31m"; NC <- "\033[0m"
log_info <- function(msg) { if (!exists("QUIET") || !isTRUE(QUIET)) cat(sprintf("%s[%s] [%s INFO]    %s%s\n", CYAN, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_step <- function(msg) { if (!exists("QUIET") || !isTRUE(QUIET)) cat(sprintf("%s[%s] [%s PROCESS] %s%s\n", YELLOW, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_warn <- function(msg) { if (!exists("QUIET") || !isTRUE(QUIET)) cat(sprintf("%s[%s] [%s WARNING] %s%s\n", ORANGE, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_success <- function(msg) { if (!exists("QUIET") || !isTRUE(QUIET)) cat(sprintf("%s[%s] [%s SUCCESS] %s%s\n", GREEN, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_error <- function(msg) { cat(sprintf("%s[%s] [%s ERROR]   %s%s\n", RED, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC), file = stderr()) }
log_sep <- function(char = "=", color = CYAN) { cat(sprintf("%s%s%s\n", color, paste(rep(char, 100), collapse = ""), NC))}

show_usage <- function() {
  log_sep("-", YELLOW)
  cat(sprintf("%sUsage:%s\n", YELLOW, NC))
  cat(sprintf("  Rscript %s <input_file> <expr_sep> <metadata> <metadata_sep> <results> <log_transform> <remove_zero_var> <threads> <quiet>\n\n", SCRIPT_NAME))
  cat(sprintf("%sArguments (all mandatory):%s\n", YELLOW, NC))
  cat(sprintf("  %sinput_file%s       Path to the expression matrix file\n", CYAN, NC))
  cat(sprintf("  %sexpr_sep%s          Field separator for expression matrix (e.g., ',', ';', 'tab')\n", CYAN, NC))
  cat(sprintf("  %smetadata%s          Path to the sample metadata file\n", CYAN, NC))
  cat(sprintf("  %smetadata_sep%s      Field separator used in metadata (e.g., ',', ';', 'tab')\n", CYAN, NC))
  cat(sprintf("  %sresults%s           Output directory for PCA plot results\n", CYAN, NC))
  cat(sprintf("  %slog_transform%s     Apply log2(x+1) transformation: 'true' or 'false'\n", CYAN, NC))
  cat(sprintf("  %sremove_zero_var%s   Remove zero variance features: 'true' or 'false'\n", CYAN, NC))
  cat(sprintf("  %sthreads%s           Number of parallel threads (positive integer)\n", CYAN, NC))
  cat(sprintf("  %squiet%s             Suppress processing log messages: 'true' or 'false'\n", CYAN, NC))
  log_sep("-", YELLOW)
}

# ------- Helper function to resolve separator values ------- #
parse_separator_inplace <- function(raw_sep) {
  sep_clean <- trimws(tolower(raw_sep))
  if (sep_clean %in% c("tab", "\\t", "\t")) {
    return("\t")
  } else if (sep_clean %in% c("comma", ",")) {
    return(",")
  } else if (sep_clean %in% c("semicolon", ";")) {
    return(";")
  } else {
    return(NULL)
  }
}

# ------- Parse command line arguments ------- #
args <- commandArgs(trailingOnly = TRUE)

# All arguments are mandatory (exact count check: 9 parameters)
if (length(args) != 9 || args[1] %in% c("-h", "--help")) {
  show_usage()
  quit(status = 1)
}

# ------- Positional Arguments Assignment ------- #
input_file      <- args[1]
raw_expr_sep    <- args[2]
metadata        <- args[3]
metadata_sep    <- args[4]
results         <- args[5]
log_transform   <- tolower(trimws(args[6]))
remove_zero_var <- tolower(trimws(args[7]))
threads         <- args[8]
quiet           <- tolower(trimws(args[9]))

# ------- Validate Quiet Parameter (upfront, required for logging) ------- #
if (!quiet %in% c("true", "false")) {
  log_error(sprintf("The quiet parameter must be 'true' or 'false' (provided: '%s')"))
  quit(status = 1)
}

# ------- Validate Boolean Parameters ------- #
if (!log_transform %in% c("true", "false")) {
  log_error(sprintf("The log_transform parameter must be 'true' or 'false' (provided: '%s')", log_transform))
  quit(status = 1)
}

if (!remove_zero_var %in% c("true", "false")) {
  log_error(sprintf("The remove_zero_var parameter must be 'true' or 'false' (provided: '%s')", remove_zero_var))
  quit(status = 1)
}

# ------- Print Pipeline Execution Context ------- #
log_sep("=", CYAN)
log_info("Pipeline Execution Context:")
cat(sprintf("  %sScript Name      :%s %s%s%s\n", CYAN, NC, GREEN, SCRIPT_NAME, NC))
cat(sprintf("  %sInput File       :%s %s%s%s\n", CYAN, NC, YELLOW, input_file, NC))
cat(sprintf("  %sExpr Sep         :%s '%s%s%s'\n", CYAN, NC, YELLOW, raw_expr_sep, NC))
cat(sprintf("  %sMetadata         :%s %s%s%s\n", CYAN, NC, YELLOW, metadata, NC))
cat(sprintf("  %sMetadata Sep     :%s '%s%s%s'\n", CYAN, NC, YELLOW, metadata_sep, NC))
cat(sprintf("  %sResults Dir      :%s %s%s%s\n", CYAN, NC, YELLOW, results, NC))
cat(sprintf("  %sLog Transform    :%s %s%s%s\n", CYAN, NC, YELLOW, log_transform, NC))
cat(sprintf("  %sRemove Zero Var  :%s %s%s%s\n", CYAN, NC, YELLOW, remove_zero_var, NC))
cat(sprintf("  %sThreads          :%s %s%s%s\n", CYAN, NC, YELLOW, threads, NC))
cat(sprintf("  %sQuiet Mode       :%s %s%s%s\n", CYAN, NC, YELLOW, quiet, NC))
log_sep("=", CYAN)
log_info("Initializing PCA Analysis Pipeline Wrapper)

# ------- Validate Threads Parameter ------- #
log_step("Validating parameters and environment...")
if (!grepl("^[0-9]+$", threads) || as.integer(threads) <= 0) {
  log_error(sprintf("The threads parameter must be a positive integer (provided: '%s')", threads))
  quit(status = 1)
}
threads_num <- as.integer(threads)

# ------- Optimize Threads Allocation ------- #
max_cores <- parallel::detectCores()
if (!is.na(max_cores) && threads_num > max_cores) {
  log_warn(sprintf("Requested threads (%d) exceed available CPU cores (%d). Capping allocation to %d.", threads_num, max_cores, max_cores))
  threads_num <- max_cores
}
Sys.setenv(OMP_NUM_THREADS = as.character(threads_num))
if (requireNamespace("RhpcBLASctl", quietly = TRUE)) {
  RhpcBLASctl::blas_set_num_threads(threads_num)
}

# ------- Check Results Directory ------- #
if (!dir.exists(results)) {
  log_warn(sprintf("Results directory '%s' does not exist. Creating it now.", results))
  dir.create(results, recursive = TRUE, showWarnings = FALSE)
}

# ------- Check Input File ------- #
if (!file.exists(input_file)) {
  log_error(sprintf("Input file '%s' does not exist.", input_file))
  quit(status = 1)
}
if (file.info(input_file)$size == 0) {
  log_error(sprintf("Input file '%s' is empty.", input_file))
  quit(status = 1)
}

# ------- Check Metadata File ------- #
if (!file.exists(metadata)) {
  log_error(sprintf("Sample metadata file '%s' does not exist.", metadata))
  quit(status = 1)
}
if (file.info(metadata)$size == 0) {
  log_error(sprintf("Sample metadata file '%s' is empty.", metadata))
  quit(status = 1)
}

# ------- Validate and Normalize Separators ------- #
expr_sep <- parse_separator_inplace(raw_expr_sep)
if (is.null(expr_sep)) {
  log_error(sprintf("Invalid expression separator provided: '%s'. Allowed values: ',', ';', '\\t', 'tab'.", raw_expr_sep))
  quit(status = 1)
}

meta_sep <- parse_separator_inplace(metadata_sep)
if (is.null(meta_sep)) {
  log_error(sprintf("Invalid metadata separator provided: '%s'. Allowed values: ',', ';', '\\t', 'tab'.", metadata_sep))
  quit(status = 1)
}

# ------- Read Input Expression Matrix ------- #
log_step("Reading expression matrix...")
tmp <- tryCatch({
  read.table(input_file, sep = expr_sep, stringsAsFactors = FALSE, header = TRUE, check.names = FALSE, row.names = 1)
}, error = function(e) {
  log_error(sprintf("Failed to parse the expression matrix file: %s", e$message))
  quit(status = 2)
})

# ------- Read Metadata File ------- #
log_step("Reading metadata file...")
metadata_df <- tryCatch({
  read.table(metadata, sep = meta_sep, stringsAsFactors = FALSE, header = TRUE, check.names = FALSE)
}, error = function(e) {
  log_error(sprintf("Failed to parse metadata file: %s", e$message))
  quit(status = 2)
})

# ------- Validate Metadata Columns ------- #
if (!"SampleName" %in% colnames(metadata_df)) {
  log_error("Column 'SampleName' not found in metadata file.")
  quit(status = 1)
}
if (!"Covariate" %in% colnames(metadata_df)) {
  log_error("Column 'Covariate' not found in metadata file.")
  quit(status = 1)
}

# ------- Align Expression Matrix and Metadata ------- #
log_step("Aligning expression matrix and metadata...")
common_samples <- intersect(colnames(tmp), metadata_df$SampleName)

if (length(common_samples) == 0) {
  log_error("No matching sample names found between expression matrix columns and metadata 'SampleName' column.")
  quit(status = 1)
}

if (length(common_samples) < ncol(tmp)) {
  log_warn(sprintf("Found metadata for %d out of %d samples in the matrix.", length(common_samples), ncol(tmp)))
}

tmp <- tmp[, common_samples, drop = FALSE]
metadata_df <- metadata_df[match(common_samples, metadata_df$SampleName), , drop = FALSE]

num_genes   <- nrow(tmp)
num_samples <- ncol(tmp)

if (num_samples < 3) {
  log_error(sprintf("At least 3 matching samples are required to compute PCA. Matched samples: %d.", num_samples))
  quit(status = 1)
}
if (num_genes < 2) {
  log_error(sprintf("Not enough genes (rows) found in the table. Rows: %d.", num_genes))
  quit(status = 1)
}

data <- tmp

# ------- Apply log2 transformation ------- #
if (log_transform == "true") {
  log_info("Applying log2(x + 1) transformation.")
  data <- log2(data + 1)
} else {
  log_info("Skipping log2 transformation.")
}

# ------- Remove zero variance features ------- #
if (remove_zero_var == "true") {
  gene_variances <- apply(data, 1, var)
  zero_var_genes <- sum(gene_variances == 0, na.rm = TRUE)
  if (zero_var_genes > 0) {
    log_warn(sprintf("Removing %d genes with zero variance across matched samples.", zero_var_genes))
    data <- data[gene_variances > 0, ]
  }
} else {
  log_info("Skipping removal of zero variance genes.")
}

# ------- Perform PCA ------- #
log_step("Computing Principal Component Analysis (PCA)...")
pca_result <- tryCatch({
  prcomp(t(data))
}, error = function(e) {
  log_error(sprintf("PCA computation failed: %s", e$message))
  quit(status = 2)
})

variance_proportion <- summary(pca_result)$importance[2, ]

# ------- Setup Colors for Covariates ------- #
Covariate_factor <- factor(metadata_df[["Covariate"]])
group_levels     <- levels(Covariate_factor)
palette_colors   <- rainbow(length(group_levels))
sample_colors    <- palette_colors[as.numeric(Covariate_factor)]

# ------- Define PDF Output Path ------- #
input_file_name <- sub("\\.[^.]*$", "", basename(input_file))
pdf_path <- file.path(results, paste0(input_file_name, "_pca.pdf"))

# ------- Generate and Save Plot ------- #
log_step("Generating PCA plot...")
tryCatch({
  pdf(pdf_path, width = 8, height = 7)
  par(mar = c(5, 4, 4, 8), xpd = TRUE)
  
  plot(
    pca_result$x[, c(1, 2)],
    main = paste0("PCA: ", basename(input_file)),
    pch = 19,
    col = sample_colors,
    cex = 1.2,
    xlab = paste0("PC1 (", signif(variance_proportion[1] * 100, 3), " % variance)"),
    ylab = paste0("PC2 (", signif(variance_proportion[2] * 100, 3), " % variance)")
  )
  
  text(
    pca_result$x[, c(1, 2)],
    labels = colnames(data),
    pos = 3,
    cex = 0.8
  )
  
  grid()
  
  legend(
    "topright",
    inset = c(-0.25, 0),
    legend = group_levels,
    col = palette_colors,
    pch = 19,
    title = "Covariate",
    bty = "n"
  )
  
  invisible(dev.off())
}, error = function(e) {
  log_error(sprintf("Failed to write the output PDF: %s", e$message))
  if (dev.cur() > 1) invisible(dev.off())
  quit(status = 2)
})

log_sep("=", CYAN)
log_success(sprintf("PCA processing completed successfully. Plot saved to: '%s'", pdf_path))
log_success("Pipeline Terminated Successfully.")