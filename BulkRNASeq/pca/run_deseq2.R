#!/usr/bin/env Rscript

# ==============================================================================
# CANONICAL WRAPPER for DESeq2 PCA pipeline script.
# ==============================================================================
SCRIPT_NAME <- "run_deseq2.R"
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
  cat(sprintf("  Rscript %s <input_file> <expr_sep> <metadata> <metadata_sep> <results> <mode> <threads> <quiet>\n\n", SCRIPT_NAME))
  cat(sprintf("%sArguments (all mandatory):%s\n", YELLOW, NC))
  cat(sprintf("  %sinput_file%s       Path to the expression matrix file\n", CYAN, NC))
  cat(sprintf("  %sexpr_sep%s          Field separator for expression matrix (e.g., ',', ';', 'tab')\n", CYAN, NC))
  cat(sprintf("  %smetadata%s          Path to the sample metadata file\n", CYAN, NC))
  cat(sprintf("  %smetadata_sep%s      Field separator used in metadata (e.g., ',', ';', 'tab')\n", CYAN, NC))
  cat(sprintf("  %sresults%s           Output directory for DESeq2 pipeline results\n", CYAN, NC))
  cat(sprintf("  %smode%s              Processing mode: 'deseq' or 'deseqnormalized'\n", CYAN, NC))
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

# All arguments are mandatory: exact count check (8 parameters)
if (length(args) != 8 || args[1] %in% c("-h", "--help")) {
  show_usage()
  quit(status = 1)
}

# ------- Positional Arguments Assignment ------- #
input_file   <- args[1]
raw_expr_sep <- args[2]
metadata     <- args[3]
metadata_sep <- args[4]
results      <- args[5]
mode         <- tolower(trimws(args[6]))
threads      <- args[7]
quiet        <- tolower(trimws(args[8]))

# ------- Validate Quiet Parameter (upfront, required for logging) ------- #
if (!quiet %in% c("true", "false")) {
  log_error(sprintf("The quiet parameter must be 'true' or 'false' (provided: '%s')", quiet))
  quit(status = 1)
}

# ------- Validate Mode Parameter ------- #
if (!mode %in% c("deseq", "deseqnormalized")) {
  log_error(sprintf("Invalid mode provided: '%s'. Allowed values: 'deseq', 'deseqnormalized'.", mode))
  quit(status = 1)
}

# ------- Print Pipeline Execution Context ------- #
log_sep("=", CYAN, quiet)
log_info("Pipeline Execution Context:", quiet)
cat(sprintf("  %sScript Name      :%s %s%s%s\n", CYAN, NC, GREEN, SCRIPT_NAME, NC))
cat(sprintf("  %sInput File       :%s %s%s%s\n", CYAN, NC, YELLOW, input_file, NC))
cat(sprintf("  %sExpr Sep         :%s '%s%s%s'\n", CYAN, NC, YELLOW, raw_expr_sep, NC))
cat(sprintf("  %sMetadata         :%s %s%s%s\n", CYAN, NC, YELLOW, metadata, NC))
cat(sprintf("  %sMetadata Sep     :%s '%s%s%s'\n", CYAN, NC, YELLOW, metadata_sep, NC))
cat(sprintf("  %sResults Dir      :%s %s%s%s\n", CYAN, NC, YELLOW, results, NC))
cat(sprintf("  %sMode             :%s %s%s%s\n", CYAN, NC, YELLOW, mode, NC))
cat(sprintf("  %sThreads          :%s %s%s%s\n", CYAN, NC, YELLOW, threads, NC))
cat(sprintf("  %sQuiet Mode       :%s %s%s%s\n", CYAN, NC, YELLOW, quiet, NC))
log_sep("=", CYAN, quiet)
log_info("Initializing DESeq2 Pipeline Wrapper", quiet)

# ------- Validate Threads Parameter ------- #
log_step("Validating parameters and environment...", quiet)
if (!grepl("^[0-9]+$", threads) || as.integer(threads) <= 0) {
  log_error(sprintf("The threads parameter must be a positive integer (provided: '%s')", threads))
  quit(status = 1)
}
threads_num <- as.integer(threads)

# ------- Optimize Threads Allocation ------- #
max_cores <- parallel::detectCores()
if (!is.na(max_cores) && threads_num > max_cores) {
  log_warn(sprintf("Requested threads (%d) exceed available CPU cores (%d). Capping allocation to %d.", threads_num, max_cores, max_cores), quiet)
  threads_num <- max_cores
}
Sys.setenv(OMP_NUM_THREADS = as.character(threads_num))

# ------- Check Results Directory ------- #
if (!dir.exists(results)) {
  log_warn(sprintf("Results directory '%s' does not exist. Creating it now.", results), quiet)
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

# ------- Load Required Libraries ------- #
log_step("Loading required packages...", quiet)
tryCatch({
  suppressPackageStartupMessages({
    library(DESeq2)
    library(ggplot2)
    library(BiocParallel)
  })
}, error = function(e) {
  log_error(sprintf("Failed to load required R packages: %s", e$message))
  quit(status = 2)
})

# Register multi-threading for DESeq2 calculations
register(MulticoreParam(workers = threads_num))

# ------- Read Input Expression Matrix ------- #
log_step("Reading expression matrix...", quiet)
mat <- tryCatch({
  read.table(input_file, row.names = 1, header = TRUE, sep = expr_sep, check.names = FALSE, stringsAsFactors = FALSE)
}, error = function(e) {
  log_error(sprintf("Failed to parse the expression matrix file: %s", e$message))
  quit(status = 2)
})

# ------- Read Metadata File ------- #
log_step("Reading metadata file...", quiet)
metadata_df <- tryCatch({
  read.table(metadata, header = TRUE, sep = meta_sep, check.names = FALSE, stringsAsFactors = FALSE)
}, error = function(e) {
  log_error(sprintf("Failed to parse metadata file: %s", e$message))
  quit(status = 2)
})

# ------- Validate Metadata Columns ------- #
sample_col_idx <- match(TRUE, casefold(colnames(metadata_df)) == "samplename")
if (is.na(sample_col_idx)) {
  log_error("Column 'SampleName' not found in metadata file.")
  quit(status = 1)
}
sample_col_name <- colnames(metadata_df)[sample_col_idx]

cov_col_idx <- match(TRUE, casefold(colnames(metadata_df)) == "covariate")
if (is.na(cov_col_idx)) {
  log_error("Column 'Covariate' not found in metadata file.")
  quit(status = 1)
}
actual_cov_col <- colnames(metadata_df)[cov_col_idx]

# ------- Align Matrix and Metadata Samples ------- #
log_step("Aligning expression matrix and metadata...", quiet)
common_samples <- intersect(colnames(mat), metadata_df[[sample_col_name]])

if (length(common_samples) < 3) {
  log_error(sprintf("DESeq2 PCA requires at least 3 matching samples between matrix and metadata. Matched: %d.", length(common_samples)))
  quit(status = 1)
}

if (length(common_samples) < ncol(mat)) {
  log_warn(sprintf("Found metadata for %d out of %d samples in matrix. Retaining common samples.", length(common_samples), ncol(mat)), quiet)
}

# Subset and align
mat <- mat[, common_samples, drop = FALSE]
metadata_df <- metadata_df[match(common_samples, metadata_df[[sample_col_name]]), , drop = FALSE]

# Prepare colData dataframe for DESeq2
coldata <- data.frame(
  row.names = common_samples,
  group = factor(metadata_df[[actual_cov_col]])
)

file_base_name <- sub("\\.[^.]*$", "", basename(input_file))

# ------- Mode 1: Standard DESeq2 PCA ------- #
if (mode == "deseq") {
  log_step("Running DESeq2 VST Transformation (Mode: deseq)...", quiet)
  
  tryCatch({
    dds <- DESeqDataSetFromMatrix(countData = as.matrix(mat), colData = coldata, design = ~ group)
    
    # Filter low-count genes (rowSums >= 10)
    dds <- dds[rowSums(counts(dds)) >= 10, ]
    
    # Variance Stabilizing Transformation
    vsd <- vst(dds, blind = TRUE)
    
    # Extract PCA data for ggplot2
    pca_data <- plotPCA(vsd, intgroup = "group", returnData = TRUE)
    pct <- round(100 * attr(pca_data, "percentVar"))
    
    p <- ggplot(pca_data, aes(PC1, PC2, color = group)) +
      geom_point(size = 4) +
      geom_text(aes(label = name), vjust = -1.5, size = 3, show.legend = FALSE) +
      xlab(paste0("PC1: ", pct[1], "% variance")) +
      ylab(paste0("PC2: ", pct[2], "% variance")) +
      ggtitle(paste0("DESeq2 PCA: ", basename(input_file))) +
      labs(color = actual_cov_col) +
      theme_bw()
    
    # Save PNG Output
    output_png <- file.path(results, paste0(file_base_name, "_deseq_pca.png"))
    ggsave(output_png, plot = p, width = 8, height = 6)
    log_success(sprintf("DESeq2 PCA plot saved to: '%s'", output_png), quiet)
  }, error = function(e) {
    log_error(sprintf("DESeq2 execution failed: %s", e$message))
    quit(status = 2)
  })

# ------- Mode 2: Normalized DESeq2 PCA ------- #
} else if (mode == "deseqnormalized") {
  log_step("Running DESeq2 VST Transformation with poscounts (Mode: deseqnormalized)...", quiet)
  
  tryCatch({
    dds <- DESeqDataSetFromMatrix(countData = as.matrix(mat), colData = coldata, design = ~ group)
    
    # Estimate size factors using poscounts method
    dds <- estimateSizeFactors(dds, type = "poscounts")
    vsd <- vst(dds, blind = TRUE)
    
    # Extract PCA data for custom ggplot2 plot
    pca_data <- plotPCA(vsd, intgroup = "group", returnData = TRUE)
    pct <- round(100 * attr(pca_data, "percentVar"))
    
    p <- ggplot(pca_data, aes(PC1, PC2, color = group)) +
      geom_point(size = 4) +
      geom_text(aes(label = name), vjust = -1.5, size = 3, show.legend = FALSE) +
      xlab(paste0("PC1: ", pct[1], "% variance")) +
      ylab(paste0("PC2: ", pct[2], "% variance")) +
      ggtitle(paste0("DESeq2 Normalized PCA: ", basename(input_file))) +
      labs(color = actual_cov_col) +
      theme_bw()

    # Save PDF Output
    output_pdf <- file.path(results, paste0(file_base_name, "_deseqNorm_pca.pdf"))
    ggsave(output_pdf, plot = p, width = 8, height = 6)
    log_success(sprintf("Design-Aware Normalized PCA plot saved to: '%s'", output_pdf), quiet)
  }, error = function(e) {
    log_error(sprintf("DESeq2 Normalized execution failed: %s", e$message))
    quit(status = 2)
  })
}

log_sep("=", CYAN, quiet)
log_success("Pipeline Terminated Successfully.", quiet)