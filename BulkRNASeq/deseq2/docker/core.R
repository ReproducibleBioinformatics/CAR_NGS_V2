#!/usr/bin/env Rscript
SCRIPT_NAME <- "core.R"
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
die <- function(msg, status = 1) {log_error(msg); quit(save = "no", status = status)}
# ------- Argument Checking: All arguments are mandatory ------- #
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 11 || (length(args) >= 1 && args[1] %in% c("-h", "--help"))) {show_usage(); quit(save = "no", status = 1)}
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
threads_arg      <- suppressWarnings(as.integer(args[10]))
quiet_arg        <- args[11]
quiet_clean <- tolower(quiet_arg)
if (!quiet_clean %in% c("true", "false")) {log_error(sprintf("The QUIET parameter must be 'true' or 'false' (provided: '%s'). Defaulting to 'false' and continuing.", quiet_arg));
} else if (quiet_clean == "true") { QUIET <- TRUE;}
# ------- Validate and optimize Threads Parameter and allocation ------- #
max_cores <- parallel::detectCores()
if (!grepl("^[0-9]+$", threads_arg) || as.integer(threads_arg) <= 0) {log_warn(paste0("Invalid threads parameter '", threads_arg, "' (must be a positive integer). Defaulting to 1.")); threads <- 1L
} else {  threads <- as.integer(threads_arg)}
if (threads > max_cores) {log_warn(paste0("Requested threads (", threads, ") exceed available CPU cores (", max_cores, "). Capping allocation to ", max_cores, ".")); threads <- max_cores}
Sys.setenv(OMP_NUM_THREADS = threads)
# ------- Validate Log2FC Threshold ------- #
if (is.na(log2fc)) { die(sprintf("The log2fc parameter must be a valid number (provided: '%s')", args[6]))}
# ------- Validate FDR Threshold ------- #
if (is.na(fdr) || fdr < 0 || fdr > 1) { die(sprintf("The fdr parameter must be a number between 0 and 1 (provided: '%s')", args[7]))}
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
if (is.na(matrix_sep_norm)) {die(sprintf("Invalid separator '%s'. Use ',' or ';' for CSV, '\\t' or 'tab' for TSV.", matrix_sep))}
matrix_sep <- matrix_sep_norm
metadata_sep_norm <- normalize_sep(metadata_sep)
if (is.na(metadata_sep_norm)) {die(sprintf("Invalid metadata separator provided: '%s'. Allowed values: ',', ';', '\\t', 'tab'.", metadata_sep))}
metadata_sep <- metadata_sep_norm
# ------- Check Results Directory ------- #
if (!dir.exists(results)) { die(sprintf("Results directory '%s' does not exist.", results))}
# ------- Check Input Matrix File ------- #
if (!file.exists(matrix_path)) {die(sprintf("Input count matrix file '%s' does not exist.", matrix_path))}
# ------- Check Metadata File ------- #
if (!file.exists(metadata)) {die(sprintf("Sample metadata file '%s' does not exist.", metadata))}
# ------- Validate Reference/Target Covariate Levels ------- #
if (ref_covar == target_covar) {die(sprintf("The ref_covar and target_covar parameters must be different (both provided: '%s')", ref_covar))}
matrix_basename <- tools::file_path_sans_ext(basename(matrix_path))
suppressPackageStartupMessages({library(DESeq2); library(data.table)})
setDTthreads(threads)
counts_df <- fread(matrix_path, header = TRUE, sep = matrix_sep, data.table = FALSE, nThread = threads)
gene_col_name <- colnames(counts_df)[1]
rownames(counts_df) <- counts_df[, 1]
counts_matrix <- counts_df[, -1]
sample_names <- colnames(counts_matrix)
log_info(sprintf("Found %d samples in count matrix.", length(sample_names)))
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
# ------- Align Metadata with Expression Matrix ------- #
coldata <- merge(data.frame(sample_id = sample_names), full_metadata, by = "sample_id", sort = FALSE)
rownames(coldata) <- coldata$sample_id
coldata <- coldata[sample_names, , drop = FALSE]
if (!all(rownames(coldata) == colnames(counts_matrix))) {die("Metadata sample IDs do not match count matrix columns.")}
condition_column <- grep("^(covariate|condition|group|treatment)$", colnames(coldata), ignore.case = TRUE, value = TRUE)
if (length(condition_column) == 0) {die("Could not detect condition/covariate column in metadata.")}
condition_column <- condition_column[1]
keep_samples <- coldata[[condition_column]] %in% c(ref_covar, target_covar)
coldata <- coldata[keep_samples, , drop = FALSE]
counts_matrix <- counts_matrix[, rownames(coldata), drop = FALSE]
log_info(sprintf("Samples retained: %d for levels: %s and %s", nrow(coldata), ref_covar, target_covar))
if (nrow(coldata) == 0) {die("No samples found matching specified target covariates.")}
coldata[[condition_column]] <- as.factor(coldata[[condition_column]])
coldata[[condition_column]] <- droplevels(coldata[[condition_column]])
if (!ref_covar %in% levels(coldata[[condition_column]])) {die(sprintf("Reference level '%s' not found in metadata condition column.", ref_covar))}
coldata[[condition_column]] <- relevel(coldata[[condition_column]], ref = ref_covar)
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
dds <- DESeqDataSetFromMatrix(countData = counts_matrix, colData = coldata, design = design_formula)
dds <- DESeq(dds)
res <- results(dds)
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
log_success("Analysis and export completed successfully!")