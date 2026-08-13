#!/usr/bin/env Rscript

SCRIPT_NAME <- "filter_de_results.R"

CYAN <- "\033[0;36m"; YELLOW <- "\033[1;33m"; ORANGE <- "\033[0;33m"; GREEN <- "\033[0;32m"; RED <- "\033[0;31m"; NC <- "\033[0m"
log_info <- function(msg) { if (!exists("QUIET") || !isTRUE(QUIET)) cat(sprintf("%s[%s] [%s INFO]    %s%s\n", CYAN, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_step <- function(msg) { if (!exists("QUIET") || !isTRUE(QUIET)) cat(sprintf("%s[%s] [%s PROCESS] %s%s\n", YELLOW, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_warn <- function(msg) { if (!exists("QUIET") || !isTRUE(QUIET)) cat(sprintf("%s[%s] [%s WARNING] %s%s\n", ORANGE, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_success <- function(msg) { if (!exists("QUIET") || !isTRUE(QUIET)) cat(sprintf("%s[%s] [%s SUCCESS] %s%s\n", GREEN, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_error <- function(msg) { cat(sprintf("%s[%s] [%s ERROR]   %s%s\n", RED, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC), file = stderr()) }
log_sep <- function(char = "=", color = CYAN) { cat(sprintf("%s%s%s\n", color, paste(rep(char, 100), collapse = ""), NC))}

QUIET <- FALSE
log_ts <- function() format(Sys.time(), "%Y-%m-%d %H:%M:%S")

show_usage <- function() {
  log_sep("-", YELLOW)
  cat(sprintf("%sUsage:%s\n", YELLOW, NC))
  cat(sprintf("  Rscript %s <de_full> <raw_counts> <norm_counts> <results> <log2fc> <padj> <threads> <quiet>\n", SCRIPT_NAME))
  cat("\n")
  cat(sprintf("%sArguments (all mandatory):%s\n", YELLOW, NC))
  cat(sprintf("  %sde_full%s      Path to the full differential expression analysis file\n", CYAN, NC))
  cat(sprintf("  %sraw_counts%s   Path to the raw counts matrix file\n", CYAN, NC))
  cat(sprintf("  %snorm_counts%s  Path to the normalized counts matrix file\n", CYAN, NC))
  cat(sprintf("  %sresults%s      Output directory for filtered results (must exist and be empty)\n", CYAN, NC))
  cat(sprintf("  %slog2fc%s       Log2 fold change threshold, non-negative (e.g., 1)\n", CYAN, NC))
  cat(sprintf("  %spadj%s         Adjusted p-value / FDR threshold (0 exclusive - 1 inclusive)\n", CYAN, NC))
  cat(sprintf("  %sthreads%s      Number of parallel threads for data.table I/O (positive integer)\n", CYAN, NC))
  cat(sprintf("  %squiet%s        Suppress processing log messages: 'true' or 'false'\n", CYAN, NC))
  log_sep("-", YELLOW)
}

# ------- Argument Checking ------- #
# All arguments are mandatory: require an exact count, no defaults/fallbacks.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 8 || args[1] %in% c("-h", "--help")) {
  show_usage()
  quit(status = 1, save = "no")
}

# ------- Positional Arguments Assignment ------- #
de_full     <- args[1]
raw_counts  <- args[2]
norm_counts <- args[3]
results     <- args[4]
log2fc_arg  <- args[5]
padj_arg    <- args[6]
threads_arg <- args[7]
quiet_arg   <- args[8]

# ------- Validate Quiet Parameter (upfront, required for logging) ------- #
# Always validate "quiet" BEFORE printing anything else, so that an invalid
# value fails immediately without emitting a partial/misleading context block.
if (!quiet_arg %in% c("true", "false")) {
  log_error(sprintf("The quiet parameter must be 'true' or 'false' (provided: '%s')", quiet_arg))
  quit(status = 1, save = "no")
}
QUIET <- identical(quiet_arg, "true")

# ------- Print Pipeline Execution Context ------- #
log_sep("=", CYAN)
log_info("Pipeline Execution Context:")
cat(sprintf("  %sScript           :%s %s%s%s\n", CYAN, NC, GREEN, SCRIPT_NAME, NC))
cat(sprintf("  %sDE Full File     :%s %s%s%s\n", CYAN, NC, YELLOW, de_full, NC))
cat(sprintf("  %sRaw Counts File  :%s %s%s%s\n", CYAN, NC, YELLOW, raw_counts, NC))
cat(sprintf("  %sNorm Counts File :%s %s%s%s\n", CYAN, NC, YELLOW, norm_counts, NC))
cat(sprintf("  %sResults Dir      :%s %s%s%s\n", CYAN, NC, YELLOW, results, NC))
cat(sprintf("  %sLog2FC Threshold :%s %s%s%s\n", CYAN, NC, YELLOW, log2fc_arg, NC))
cat(sprintf("  %sPadj Threshold   :%s %s%s%s\n", CYAN, NC, YELLOW, padj_arg, NC))
cat(sprintf("  %sThreads          :%s %s%s%s\n", CYAN, NC, YELLOW, threads_arg, NC))
cat(sprintf("  %sQuiet Mode       :%s %s%s%s\n", CYAN, NC, YELLOW, quiet_arg, NC))
log_sep("=", CYAN)
log_info("Initializing DE Results Filter Execution")

# ------- Validate Threads Parameter ------- #
log_step("Validating parameters and environment...")
if (!grepl("^[0-9]+$", threads_arg) || as.integer(threads_arg) <= 0) {
  log_error(sprintf("The threads parameter must be a positive integer (provided: '%s')", threads_arg))
  quit(status = 1, save = "no")
}
threads <- as.integer(threads_arg)

# ------- Check Results Directory ------- #
if (!dir.exists(results)) {
  log_error(sprintf("Results directory '%s' does not exist.", results))
  quit(status = 1, save = "no")
}
if (length(list.files(results, all.files = TRUE, no.. = TRUE)) > 0) {
  log_error(sprintf("Results directory '%s' is not empty. Terminating pipeline to prevent overwriting existing data.", results))
  quit(status = 1, save = "no")
}

# ------- Check Input Files ------- #
if (!file.exists(de_full)) {
  log_error(sprintf("DE_full file '%s' does not exist.", de_full))
  quit(status = 1, save = "no")
}
if (!file.exists(raw_counts)) {
  log_error(sprintf("Raw counts file '%s' does not exist.", raw_counts))
  quit(status = 1, save = "no")
}
if (!file.exists(norm_counts)) {
  log_error(sprintf("Normalized counts file '%s' does not exist.", norm_counts))
  quit(status = 1, save = "no")
}

# ------- Validate log2fc Parameter ------- #
if (!grepl("^-?[0-9]+([.][0-9]+)?$", log2fc_arg)) {
  log_error(sprintf("The log2fc parameter must be numeric (provided: '%s')", log2fc_arg))
  quit(status = 1, save = "no")
}
lfc_threshold <- as.numeric(log2fc_arg)
if (lfc_threshold < 0) {
  log_error(sprintf("The log2fc parameter must be non-negative, since it represents an absolute fold-change threshold (provided: '%s')", log2fc_arg))
  quit(status = 1, save = "no")
}

# ------- Validate padj Parameter ------- #
if (!grepl("^[0-9]+([.][0-9]+)?$", padj_arg)) {
  log_error(sprintf("The padj parameter must be numeric (provided: '%s')", padj_arg))
  quit(status = 1, save = "no")
}
padj_threshold <- as.numeric(padj_arg)
if (padj_threshold <= 0 || padj_threshold > 1) {
  log_error(sprintf("The padj parameter must be between 0 (exclusive) and 1 (inclusive) (provided: '%s')", padj_arg))
  quit(status = 1, save = "no")
}

log_success("All input parameters validated successfully.")
log_sep("-", YELLOW)

# ==============================================================================
# EXIT CODE SCHEME
# exit 1 -> usage / argument / input / parameter validation errors (everything above this line)
# exit 2 -> missing required statistical columns in the DE_full file
# exit 3 -> failure while writing output files
# ==============================================================================

# ------- Load required libraries ------- #
suppressPackageStartupMessages(library(data.table))

# Configure parallel I/O threads for data.table
setDTthreads(threads)
log_info(sprintf("data.table threads allocated (I/O): %d", getDTthreads()))

# ------- Core Processing Step 1: Load input data matrices ------- #
log_step("Loading input data matrices...")
# Keep data as data.table (data.table = TRUE) for fast native C-level subsetting
de_full_dt     <- fread(de_full, header = TRUE, data.table = TRUE, nThread = threads)
raw_counts_dt  <- fread(raw_counts, header = TRUE, data.table = TRUE, nThread = threads)
norm_counts_dt <- fread(norm_counts, header = TRUE, data.table = TRUE, nThread = threads)
log_success("Input data matrices loaded.")

# ------- Validate Required Statistical Columns ------- #
required_cols <- c("padj", "log2FoldChange")
missing_cols  <- setdiff(required_cols, colnames(de_full_dt))
if (length(missing_cols) > 0) {
  log_error(sprintf("Missing required column(s) in DE_full file: %s", paste(missing_cols, collapse = ", ")))
  quit(status = 2, save = "no")
}

# Identify primary gene ID columns (assumed to be the first column)
gene_col_de   <- colnames(de_full_dt)[1]
gene_col_raw  <- colnames(raw_counts_dt)[1]
gene_col_norm <- colnames(norm_counts_dt)[1]

# ------- Core Processing Step 2: Apply statistical filters ------- #
log_step("Applying statistical filters...")

# Filter out rows with NA values in padj or log2FoldChange
de_clean <- de_full_dt[!is.na(padj) & !is.na(log2FoldChange)]

# Identify genes passing both threshold criteria
de_filtered       <- de_clean[padj <= padj_threshold & abs(log2FoldChange) >= lfc_threshold]
significant_genes <- de_filtered[[gene_col_de]]

log_info(sprintf("Total input genes analyzed: %d", nrow(de_full_dt)))
log_info(sprintf("Significant genes passing threshold criteria: %d", length(significant_genes)))

# ------- Core Processing Step 3: Filter count matrices ------- #
raw_filtered  <- raw_counts_dt[get(gene_col_raw) %in% significant_genes]
norm_filtered <- norm_counts_dt[get(gene_col_norm) %in% significant_genes]

# Sanity check for matching gene IDs across files
if (length(significant_genes) > 0 && nrow(raw_filtered) == 0) {
  log_warn("None of the significant gene IDs were found in the raw counts matrix. Check primary ID column formatting across files.")
}

# ------- Core Processing Step 4: Write output files ------- #
log_step("Writing output files to target directory...")

write_result <- tryCatch({
  fwrite(de_full_dt, file.path(results, "DE_FULL.txt"), sep = "\t", row.names = FALSE, quote = FALSE, nThread = threads)
  log_success("[Generated] DE_FULL.txt")

  fwrite(de_filtered, file.path(results, "DE_Filtered.txt"), sep = "\t", row.names = FALSE, quote = FALSE, nThread = threads)
  log_success("[Generated] DE_Filtered.txt")

  fwrite(raw_filtered, file.path(results, "DE_counts.txt"), sep = "\t", row.names = FALSE, quote = FALSE, nThread = threads)
  log_success("[Generated] DE_counts.txt")

  fwrite(norm_filtered, file.path(results, "DE_normalizedCounts.txt"), sep = "\t", row.names = FALSE, quote = FALSE, nThread = threads)
  log_success("[Generated] DE_normalizedCounts.txt")
  TRUE
}, error = function(e) {
  log_error(sprintf("Failed to write output files: %s", conditionMessage(e)))
  FALSE
})

if (!isTRUE(write_result)) {
  quit(status = 3, save = "no")
}

# ------- Apply Standard Permissions ------- #
output_files <- list.files(results, full.names = TRUE)
if (length(output_files) > 0) {
  Sys.chmod(output_files, mode = "0777")
}

# ------- Final Output Check ------- #
log_sep()
log_success("Pipeline Terminated Successfully.")
