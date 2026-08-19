#!/usr/bin/env Rscript
# ==============================================================================
# Script: core.R
# Description: End-to-end Differential Gene Expression analysis using DESeq2.
#
# NAMING CONVENTIONS (mirrors sample.sh):
# - The results/output directory variable is ALWAYS named "results" (never
#   "output_folder" / "outDir" / anything else).
# - The metadata file path variable is ALWAYS named "metadata".
# - The metadata field separator variable is ALWAYS named "metadata_sep".
# - Every script-defined variable (arguments, locals, loop counters, temp
#   vars) uses all-lowercase names. Only the fixed constants shared across
#   every script - SCRIPT_NAME, QUIET, NC/CYAN/YELLOW/ORANGE/GREEN/RED - keep
#   the existing uppercase convention.
# ==============================================================================

# ------- Script Name (mirrors DOCKER_NAME in the bash wrapper) ------- #
get_script_name <- function() {
  raw_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", raw_args, value = TRUE)
  if (length(file_arg) > 0) {
    return(basename(sub("^--file=", "", file_arg[1])))
  }
  return("core.R")
}
SCRIPT_NAME <- get_script_name()
CYAN <- "\033[0;36m"; YELLOW <- "\033[1;33m"; ORANGE <- "\033[0;33m"; GREEN <- "\033[0;32m"; RED <- "\033[0;31m"; NC <- "\033[0m"
log_info <- function(msg) { if (!exists("QUIET") || !isTRUE(QUIET)) cat(sprintf("%s[%s] [%s INFO]    %s%s\n", CYAN, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_step <- function(msg) { if (!exists("QUIET") || !isTRUE(QUIET)) cat(sprintf("%s[%s] [%s PROCESS] %s%s\n", YELLOW, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_warn <- function(msg) { if (!exists("QUIET") || !isTRUE(QUIET)) cat(sprintf("%s[%s] [%s WARNING] %s%s\n", ORANGE, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_success <- function(msg) { if (!exists("QUIET") || !isTRUE(QUIET)) cat(sprintf("%s[%s] [%s SUCCESS] %s%s\n", GREEN, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_error <- function(msg) { cat(sprintf("%s[%s] [%s ERROR]   %s%s\n", RED, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC), file = stderr()) }
log_sep <- function(char = "=", color = CYAN) { cat(sprintf("%s%s%s\n", color, paste(rep(char, 100), collapse = ""), NC))}

QUIET <- FALSE
log_timestamp <- function() format(Sys.time(), "%Y-%m-%d %H:%M:%S")

# ------- Fatal Error Helper (log + non-zero exit, mirrors "exit 1") ------- #
die <- function(msg, status = 1) {
  log_error(msg)
  quit(save = "no", status = status)
}

# ------- Display Script Usage and Help Menu ------- #
show_usage <- function() {
  log_sep("-", YELLOW)
  cat(sprintf("%sUsage:%s\n", YELLOW, NC))
  cat(sprintf("  Rscript %s <results> <matrix_path> <matrix_sep> <metadata> <metadata_sep> <log2fc> <fdr> <ref_covar> <target_covar> <threads> <quiet>\n", SCRIPT_NAME))
  cat("\n")
  cat(sprintf("%sArguments (all mandatory):%s\n", YELLOW, NC))
  cat(sprintf("  %sresults%s        Output directory for differential expression results\n", CYAN, NC))
  cat(sprintf("  %smatrix_path%s    Path to the count matrix file (.csv, .tsv, .txt)\n", CYAN, NC))
  cat(sprintf("  %smatrix_sep%s     Field separator used in count matrix (e.g., ',' ';' or 'tab')\n", CYAN, NC))
  cat(sprintf("  %smetadata%s       Path to the sample metadata table\n", CYAN, NC))
  cat(sprintf("  %smetadata_sep%s   Field separator used in metadata file (e.g., ',' ';' or 'tab')\n", CYAN, NC))
  cat(sprintf("  %slog2fc%s         Absolute Log2 Fold Change threshold for filtering (e.g., 1.0)\n", CYAN, NC))
  cat(sprintf("  %sfdr%s            FDR / Adjusted p-value significance threshold (e.g., 0.05)\n", CYAN, NC))
  cat(sprintf("  %sref_covar%s      Baseline/Control group level in metadata (e.g., 'control')\n", CYAN, NC))
  cat(sprintf("  %starget_covar%s   Treatment/Target group level in metadata (e.g., 'treated')\n", CYAN, NC))
  cat(sprintf("  %sthreads%s        Number of parallel threads (positive integer)\n", CYAN, NC))
  cat(sprintf("  %squiet%s          Suppress processing log messages: 'true' or 'false'\n", CYAN, NC))
  log_sep("-", YELLOW)
}

# ------- Argument Checking ------- #
# All arguments are mandatory: always check for the exact expected count.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 11 || (length(args) >= 1 && args[1] %in% c("-h", "--help"))) {
  show_usage()
  quit(save = "no", status = 1)
}

# ------- Positional Arguments Assignment ------- #
results          <- args[1]
matrix_path      <- args[2]
matrix_sep       <- args[3]
metadata         <- args[4]
metadata_sep     <- args[5]
log2fc           <- as.numeric(args[6])
fdr              <- as.numeric(args[7])
ref_covar        <- args[8]
target_covar     <- args[9]
threads          <- suppressWarnings(as.integer(args[10]))
quiet            <- args[11]

# ------- Validate Quiet Parameter (upfront, required for logging) ------- #
# Always validate "quiet" BEFORE printing anything else, so that an invalid
# value fails immediately without emitting a partial/misleading context block.
if (!quiet %in% c("true", "false")) {
  die(sprintf("The quiet parameter must be 'true' or 'false' (provided: '%s')", quiet))
}
QUIET <- (quiet == "true")

# ------- Print Pipeline Execution Context ------- #
log_sep("=", CYAN)
log_info("Pipeline Execution Context:")
cat(sprintf("  %sScript          :%s %s%s%s\n", CYAN, NC, GREEN, SCRIPT_NAME, NC))
cat(sprintf("  %sResults Dir     :%s %s%s%s\n", CYAN, NC, YELLOW, results, NC))
cat(sprintf("  %sMatrix File     :%s %s%s%s\n", CYAN, NC, YELLOW, matrix_path, NC))
cat(sprintf("  %sMatrix Sep      :%s '%s%s%s'\n", CYAN, NC, YELLOW, matrix_sep, NC))
cat(sprintf("  %sMetadata        :%s %s%s%s\n", CYAN, NC, YELLOW, metadata, NC))
cat(sprintf("  %sMetadata Sep    :%s '%s%s%s'\n", CYAN, NC, YELLOW, metadata_sep, NC))
cat(sprintf("  %sLog2FC Threshold:%s %s%s%s\n", CYAN, NC, YELLOW, args[6], NC))
cat(sprintf("  %sFDR Threshold   :%s %s%s%s\n", CYAN, NC, YELLOW, args[7], NC))
cat(sprintf("  %sReference Level :%s %s%s%s\n", CYAN, NC, YELLOW, ref_covar, NC))
cat(sprintf("  %sTarget Level    :%s %s%s%s\n", CYAN, NC, YELLOW, target_covar, NC))
cat(sprintf("  %sThreads         :%s %s%s%s\n", CYAN, NC, YELLOW, args[10], NC))
cat(sprintf("  %sQuiet Mode      :%s %s%s%s\n", CYAN, NC, YELLOW, quiet, NC))
log_sep("=", CYAN)
log_info("Initializing DESeq2 Core Analysis Script")

# ------- Validate Threads Parameter ------- #
log_step("Validating parameters and environment...")
if (is.na(threads) || threads < 1) {
  die(sprintf("The threads parameter must be a positive integer (provided: '%s')", args[10]))
}

# ------- Validate Log2FC Threshold ------- #
if (is.na(log2fc)) {
  die(sprintf("The log2fc parameter must be a valid number (provided: '%s')", args[6]))
}

# ------- Validate FDR Threshold ------- #
if (is.na(fdr) || fdr < 0 || fdr > 1) {
  die(sprintf("The fdr parameter must be a number between 0 and 1 (provided: '%s')", args[7]))
}

# ------- Normalize Separators ------- #
# Accepts ',' ';' 'tab' '\t' (case-insensitive), same convention as the bash
# wrapper's parse_separator_inplace().
normalize_sep <- function(sep) {
  sep_clean <- tolower(trimws(sep))
  if (sep_clean %in% c("tab", "\\t")) return("\t")
  if (sep_clean %in% c(",", ";")) return(sep_clean)
  return(NA_character_)
}
matrix_sep_norm <- normalize_sep(matrix_sep)
if (is.na(matrix_sep_norm)) {
  die(sprintf("Invalid separator '%s'. Use ',' or ';' for CSV, '\\t' or 'tab' for TSV.", matrix_sep))
}
matrix_sep <- matrix_sep_norm

metadata_sep_norm <- normalize_sep(metadata_sep)
if (is.na(metadata_sep_norm)) {
  die(sprintf("Invalid metadata separator provided: '%s'. Allowed values: ',', ';', '\\t', 'tab'.", metadata_sep))
}
metadata_sep <- metadata_sep_norm

# ------- Check Results Directory ------- #
# Always call the destination directory "Results directory" - never mix
# "Results directory" and "Output directory" for the same variable.
if (!dir.exists(results)) {
  die(sprintf("Results directory '%s' does not exist.", results))
}

# ------- Check Input Matrix File ------- #
if (!file.exists(matrix_path)) {
  die(sprintf("Input count matrix file '%s' does not exist.", matrix_path))
}

# ------- Check Metadata File ------- #
if (!file.exists(metadata)) {
  die(sprintf("Sample metadata file '%s' does not exist.", metadata))
}

# ------- Validate Reference/Target Covariate Levels ------- #
if (ref_covar == target_covar) {
  die(sprintf("The ref_covar and target_covar parameters must be different (both provided: '%s')", ref_covar))
}

matrix_basename <- tools::file_path_sans_ext(basename(matrix_path))

# Load required packages
suppressPackageStartupMessages({
  library(DESeq2)
  library(data.table)
})

setDTthreads(threads)

log_sep("-", YELLOW)
log_step("Loading raw count matrix and metadata...")

# Load count matrix with specified separator
counts_df <- fread(matrix_path, header = TRUE, sep = matrix_sep, data.table = FALSE, nThread = threads)

gene_col_name <- colnames(counts_df)[1]
rownames(counts_df) <- counts_df[, 1]
counts_matrix <- counts_df[, -1]

sample_names <- colnames(counts_matrix)
log_info(sprintf("Found %d samples in count matrix.", length(sample_names)))

# Load Metadata
full_metadata <- fread(metadata, header = TRUE, sep = metadata_sep, data.table = FALSE, nThread = threads)

# ------- Sample Alignment via SampleName Column ------- #
samplename_col <- grep("^samplename$", colnames(full_metadata), ignore.case = TRUE, value = TRUE)

if (length(samplename_col) > 0) {
  log_info(sprintf("Sample matching performed via metadata column '%s'.", samplename_col[1]))
  full_metadata$sample_id <- full_metadata[[samplename_col[1]]]
} else {
  log_warn("Column 'SampleName' not found. Falling back to the first metadata column.")
  full_metadata$sample_id <- full_metadata[[1]]
}

full_metadata <- full_metadata[!duplicated(full_metadata$sample_id), ]

# Align Metadata with Expression Matrix
coldata <- merge(data.frame(sample_id = sample_names), full_metadata, by = "sample_id", sort = FALSE)
rownames(coldata) <- coldata$sample_id
coldata <- coldata[sample_names, , drop = FALSE]

if (!all(rownames(coldata) == colnames(counts_matrix))) {
  die("Metadata sample IDs do not match count matrix columns.")
}

condition_column <- grep("^(covariate|condition|group|treatment)$", colnames(coldata), ignore.case = TRUE, value = TRUE)
if (length(condition_column) == 0) {
  die("Could not detect condition/covariate column in metadata.")
}
condition_column <- condition_column[1]

log_sep("-", YELLOW)
log_step("Filtering samples for target covariates...")

keep_samples <- coldata[[condition_column]] %in% c(ref_covar, target_covar)
coldata <- coldata[keep_samples, , drop = FALSE]
counts_matrix <- counts_matrix[, rownames(coldata), drop = FALSE]

log_info(sprintf("Samples retained: %d for levels: %s and %s", nrow(coldata), ref_covar, target_covar))

if (nrow(coldata) == 0) {
  die("No samples found matching specified target covariates.")
}

coldata[[condition_column]] <- as.factor(coldata[[condition_column]])
coldata[[condition_column]] <- droplevels(coldata[[condition_column]])

if (!ref_covar %in% levels(coldata[[condition_column]])) {
  die(sprintf("Reference level '%s' not found in metadata condition column.", ref_covar))
}
coldata[[condition_column]] <- relevel(coldata[[condition_column]], ref = ref_covar)

# Batch Effect Detection
batch_column <- grep("^batch$", colnames(coldata), ignore.case = TRUE, value = TRUE)
use_batch <- FALSE

if (length(batch_column) > 0) {
  valid_batches <- na.omit(coldata[[batch_column]])
  valid_batches <- valid_batches[valid_batches != ""]
  if (length(unique(valid_batches)) > 1) {
    use_batch <- TRUE
    coldata[[batch_column]] <- as.factor(coldata[[batch_column]])
    log_info(sprintf("Batch effect detected and included in design ('%s').", batch_column))
  }
}

design_string <- if (use_batch) paste("~", batch_column, "+", condition_column) else paste("~", condition_column)
design_formula <- as.formula(design_string)

log_info(sprintf("Applied Design Formula: %s", design_string))

log_sep("-", YELLOW)
log_step("Building DESeqDataSet & Running Differential Expression...")

dds <- DESeqDataSetFromMatrix(countData = counts_matrix,
                               colData = coldata,
                               design = design_formula)

dds <- DESeq(dds)
res <- results(dds)

log_sep("-", YELLOW)
log_step("Saving output files...")

res_df <- data.frame(Gene = rownames(res), res, check.names = FALSE)
colnames(res_df)[1] <- gene_col_name

# --- Output 1: DE_FULL.txt ---
de_full_path <- file.path(results, "DE_FULL.txt")
fwrite(res_df, de_full_path, sep = "\t", row.names = FALSE, quote = FALSE, nThread = threads)
log_success(sprintf("Saved DE_FULL.txt (Total genes: %d)", nrow(res_df)))

# --- Output 2: DE_filtered.txt ---
res_clean <- res_df[!is.na(res_df$padj) & !is.na(res_df$log2FoldChange), ]
de_filtered <- res_clean[abs(res_clean$log2FoldChange) >= log2fc & res_clean$padj <= fdr, ]

de_filtered_path <- file.path(results, "DE_filtered.txt")
fwrite(de_filtered, de_filtered_path, sep = "\t", row.names = FALSE, quote = FALSE, nThread = threads)

significant_genes <- de_filtered[[gene_col_name]]
log_success(sprintf("Saved DE_filtered.txt (DE genes: %d)", length(significant_genes)))

# --- Output 3: <matrix>_DE.txt ---
raw_counts_sub <- counts_df[, c(gene_col_name, colnames(counts_matrix))]
raw_de_filtered <- raw_counts_sub[raw_counts_sub[[gene_col_name]] %in% significant_genes, ]

raw_out_path <- file.path(results, paste0(matrix_basename, "_DE.txt"))
fwrite(raw_de_filtered, raw_out_path, sep = "\t", row.names = FALSE, quote = FALSE, nThread = threads)
log_success(sprintf("Saved %s", basename(raw_out_path)))

# --- Output 4: <matrix>_normalized_DE.txt ---
norm_counts_mat <- log2(counts(dds, normalized = TRUE) + 1)
norm_counts_df <- data.frame(Gene = rownames(norm_counts_mat), norm_counts_mat, check.names = FALSE)
colnames(norm_counts_df)[1] <- gene_col_name

norm_de_filtered <- norm_counts_df[norm_counts_df[[gene_col_name]] %in% significant_genes, ]

norm_out_path <- file.path(results, paste0(matrix_basename, "_normalized_DE.txt"))
fwrite(norm_de_filtered, norm_out_path, sep = "\t", row.names = FALSE, quote = FALSE, nThread = threads)
log_success(sprintf("Saved %s", basename(norm_out_path)))

system(paste0("chmod 777 ", shQuote(paste0(results, "/")), "*"), ignore.stderr = TRUE)

log_sep("=", CYAN)
log_success("Analysis and export completed successfully!")
