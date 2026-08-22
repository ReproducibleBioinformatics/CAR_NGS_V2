#!/usr/bin/env Rscript
SCRIPT_NAME <- "run_deseq2.R"
CYAN <- "\033[0;36m"; YELLOW <- "\033[1;33m"; ORANGE <- "\033[0;33m"; GREEN <- "\033[0;32m"; RED <- "\033[0;31m"; NC <- "\033[0m"
QUIET <- FALSE
log_info    <- function(msg) { if (!QUIET) cat(sprintf("%s[%s] [%s INFO]    %s%s\n", CYAN, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_step    <- function(msg) { if (!QUIET) cat(sprintf("%s[%s] [%s PROCESS] %s%s\n", YELLOW, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_warn    <- function(msg) { if (!QUIET) cat(sprintf("%s[%s] [%s WARNING] %s%s\n", ORANGE, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_success <- function(msg) { if (!QUIET) cat(sprintf("%s[%s] [%s SUCCESS] %s%s\n", GREEN, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_error   <- function(msg) { cat(sprintf("%s[%s] [%s ERROR]   %s%s\n", RED, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC), file = stderr()) }
log_sep     <- function(char = "=", color = CYAN) { if (!QUIET) cat(sprintf("%s%s%s\n", color, paste(rep(char, 100), collapse = ""), NC)) }
show_usage <- function() {
  log_sep("-", YELLOW)
  cat(sprintf("%sUsage:%s\n", YELLOW, NC))
  cat(sprintf("  Rscript %s <input_file> <expr_sep> <metadata> <metadata_sep> <results> <mode> <blind> <threads> <quiet>\n\n", SCRIPT_NAME))
  cat(sprintf("%sArguments (all mandatory):%s\n", YELLOW, NC))
  cat(sprintf("  %sinput_file%s       Path to the expression matrix file\n", CYAN, NC))
  cat(sprintf("  %sexpr_sep%s          Field separator for expression matrix (e.g., ',', ';', 'tab')\n", CYAN, NC))
  cat(sprintf("  %smetadata%s          Path to the sample metadata file\n", CYAN, NC))
  cat(sprintf("  %smetadata_sep%s      Field separator used in metadata (e.g., ',', ';', 'tab')\n", CYAN, NC))
  cat(sprintf("  %sresults%s           Output directory for DESeq2 pipeline results\n", CYAN, NC))
  cat(sprintf("  %smode%s              Processing mode: 'deseq' or 'deseqnormalized'\n", CYAN, NC))
  cat(sprintf("  %sblind%s             Whether to ignore the experimental design during transformation\n", CYAN, NC))  
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
# ------- Argument Checking: All arguments are mandatory ------- #
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 9 || args[1] %in% c("-h", "--help")) {show_usage(); quit(status = 1)}
# ------- Positional Arguments Assignment ------- #
input_file   <- args[1]
raw_expr_sep <- args[2]
metadata     <- args[3]
metadata_sep <- args[4]
results      <- args[5]
mode         <- tolower(trimws(args[6]))
blind        <- tolower(trimws(args[7]))
threads_arg  <- args[8]
quiet_arg    <- tolower(trimws(args[9]))
# ------- Validate Quiet Parameter (upfront, required for logging) ------- #
quiet_clean <- tolower(quiet_arg)
if (!quiet_clean %in% c("true", "false")) {log_error(sprintf("The QUIET parameter must be 'true' or 'false' (provided: '%s'). Defaulting to 'false' and continuing.", quiet_arg));
} else if (quiet_clean == "true") { QUIET <- TRUE;}
# ------- Validate Mode Parameter ------- #
if (!mode %in% c("deseq", "deseqnormalized")) {log_error(sprintf("Invalid mode provided: '%s'. Allowed values: 'deseq', 'deseqnormalized'.", mode)); quit(status = 1)}
# ------- Validate blind Parameter ------- #
if (!blind %in% c("true", "false")) {log_error(sprintf("Invalid blind provided: '%s'. Allowed values: 'true', 'false'.", blind)); quit(status = 1)}
blind <- blind == "true"
# ------- Validate and optimize Threads Parameter and allocation ------- #
max_cores <- parallel::detectCores()
if (!grepl("^[0-9]+$", threads_arg) || as.integer(threads_arg) <= 0) {log_warn(paste0("Invalid threads parameter '", threads_arg, "' (must be a positive integer). Defaulting to 1.")); threads <- 1L
} else {  threads <- as.integer(threads_arg)}
if (threads > max_cores) {log_warn(paste0("Requested threads (", threads, ") exceed available CPU cores (", max_cores, "). Capping allocation to ", max_cores, ".")); threads <- max_cores}
Sys.setenv(OMP_NUM_THREADS = threads)
# ------- Check Results Directory ------- #
if (!dir.exists(results)) { log_warn(sprintf("Results directory '%s' does not exist. Creating it now.", results)); dir.create(results, recursive = TRUE, showWarnings = FALSE)}
# ------- Check Input File ------- #
if (!file.exists(input_file)) { log_error(sprintf("Input file '%s' does not exist.", input_file)); quit(status = 1)}
if (file.info(input_file)$size == 0) { log_error(sprintf("Input file '%s' is empty.", input_file)); quit(status = 1)}
# ------- Check Metadata File ------- #
if (!file.exists(metadata)) { log_error(sprintf("Sample metadata file '%s' does not exist.", metadata)); quit(status = 1)}
if (file.info(metadata)$size == 0) { log_error(sprintf("Sample metadata file '%s' is empty.", metadata)); quit(status = 1)}
# ------- Validate and Normalize Separators ------- #
expr_sep <- parse_separator_inplace(raw_expr_sep)
if (is.null(expr_sep)) { log_error(sprintf("Invalid expression separator provided: '%s'. Allowed values: ',', ';', '\\t', 'tab'.", raw_expr_sep)); quit(status = 1)}
meta_sep <- parse_separator_inplace(metadata_sep)
if (is.null(meta_sep)) { log_error(sprintf("Invalid metadata separator provided: '%s'. Allowed values: ',', ';', '\\t', 'tab'.", metadata_sep)); quit(status = 1)}
# ------- Load Required Libraries ------- #
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
register(MulticoreParam(workers = threads))
# ------- Read Input Expression Matrix ------- #
mat <- tryCatch({
  read.table(input_file, row.names = 1, header = TRUE, sep = expr_sep, check.names = FALSE, stringsAsFactors = FALSE)
}, error = function(e) {
  log_error(sprintf("Failed to parse the expression matrix file: %s", e$message))
  quit(status = 2)
})
# ------- Read Metadata File ------- #
metadata_df <- tryCatch({
  read.table(metadata, header = TRUE, sep = meta_sep, check.names = FALSE, stringsAsFactors = FALSE)
}, error = function(e) {
  log_error(sprintf("Failed to parse metadata file: %s", e$message))
  quit(status = 2)
})
# ------- Validate Metadata Columns ------- #
sample_col_idx <- match(TRUE, casefold(colnames(metadata_df)) == "samplename")
if (is.na(sample_col_idx)) { log_error("Column 'SampleName' not found in metadata file."); quit(status = 1)}
sample_col_name <- colnames(metadata_df)[sample_col_idx]
cov_col_idx <- match(TRUE, casefold(colnames(metadata_df)) == "covariate")
if (is.na(cov_col_idx)) { log_error("Column 'Covariate' not found in metadata file."); quit(status = 1)}
actual_cov_col <- colnames(metadata_df)[cov_col_idx]
# ------- Align Matrix and Metadata Samples ------- #
common_samples <- intersect(colnames(mat), metadata_df[[sample_col_name]])
if (length(common_samples) < 3) { log_error(sprintf("DESeq2 PCA requires at least 3 matching samples between matrix and metadata. Matched: %d.", length(common_samples))); quit(status = 1)}
if (length(common_samples) < ncol(mat)) { log_warn(sprintf("Found metadata for %d out of %d samples in matrix. Retaining common samples.", length(common_samples), ncol(mat)))}
mat <- mat[, common_samples, drop = FALSE]
metadata_df <- metadata_df[match(common_samples, metadata_df[[sample_col_name]]), , drop = FALSE]
coldata <- data.frame(row.names = common_samples,group = factor(metadata_df[[actual_cov_col]]))
file_base_name <- sub("\\.[^.]*$", "", basename(input_file))
# ------- Mode 1: Standard DESeq2 PCA ------- #
if (mode == "deseq") {
  log_step("Running DESeq2 VST Transformation (Mode: deseq)...")
  tryCatch({
    dds <- DESeqDataSetFromMatrix(countData = as.matrix(mat), colData = coldata, design = ~ group)
    dds <- dds[rowSums(counts(dds)) >= 10, ]
    vsd <- vst(dds, blind = blind)
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
    output_png <- file.path(results, paste0(file_base_name, "_deseq_pca.png"))
    ggsave(output_png, plot = p, width = 8, height = 6)
    log_success(sprintf("DESeq2 PCA plot saved to: '%s'", output_png))
  }, error = function(e) {
    log_error(sprintf("DESeq2 execution failed: %s", e$message))
    quit(status = 2)
  })
# ------- Mode 2: Normalized DESeq2 PCA ------- #
} else if (mode == "deseqnormalized") {
  log_step("Running DESeq2 VST Transformation with poscounts (Mode: deseqnormalized)...")
  tryCatch({
    dds <- DESeqDataSetFromMatrix(countData = as.matrix(mat), colData = coldata, design = ~ group)
    dds <- estimateSizeFactors(dds, type = "poscounts")
    vsd <- vst(dds, blind = blind)
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
    output_pdf <- file.path(results, paste0(file_base_name, "_deseqNorm_pca.pdf"))
    ggsave(output_pdf, plot = p, width = 8, height = 6)
    log_success(sprintf("Design-Aware Normalized PCA plot saved to: '%s'", output_pdf))
  }, error = function(e) {
    log_error(sprintf("DESeq2 Normalized execution failed: %s", e$message))
    quit(status = 2)
  })
}