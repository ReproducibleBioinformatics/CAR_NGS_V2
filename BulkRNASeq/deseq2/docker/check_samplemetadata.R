#!/usr/bin/env Rscript
SCRIPT_NAME <- "check_samplemetadata.R"
CYAN <- "\033[0;36m"; YELLOW <- "\033[1;33m"; GREEN <- "\033[0;32m"; RED <- "\033[0;31m"; NC <- "\033[0m"
get_timestamp <- function() {format(Sys.time(), "%Y-%m-%d %H:%M:%S")}
log_success <- function(msg) {if (exists("QUIET") && isTRUE(QUIET)) return(invisible(NULL)); cat(sprintf("%s[%s] [%s SUCCESS] %s%s\n", GREEN, get_timestamp(), SCRIPT_NAME, msg, NC))}
log_error <- function(msg) {cat(sprintf("%s[%s] [%s ERROR]   %s%s\n", RED, get_timestamp(), SCRIPT_NAME, msg, NC), file = stderr())}
log_sep <- function(char = "=", color = CYAN) { cat(sprintf("%s%s%s\n", color, paste(rep(char, 100), collapse = ""), NC))}
show_usage <- function() {
  log_sep("-", YELLOW)
  cat(sprintf("%sUsage:%s\n", YELLOW, NC))
  cat(sprintf("  Rscript %s <METADATA_FILE> <SEPARATOR> <SEQ_TYPE> <QUIET>\n\n", SCRIPT_NAME))
  cat(sprintf("%sArguments (all mandatory):%s\n", YELLOW, NC))
  cat(sprintf("  %sMETADATA_FILE%s Path to the metadata CSV/TSV file\n", CYAN, NC))
  cat(sprintf("  %sSEPARATOR%s     Field separator used in file, e.g. ';' or ','\n", CYAN, NC))
  cat(sprintf("  %sSEQ_TYPE%s      Sequencing mode: 'se' (Single-End) or 'pe' (Paired-End). Pass '' or 'null' to skip this check\n", CYAN, NC))
  cat(sprintf("  %sQUIET%s         Suppress non-error log messages: 'true' or 'false'\n\n", CYAN, NC))
  cat(sprintf("%sOptions:%s\n", YELLOW, NC))
  cat(sprintf("  %s-h, --help%s    Show this help message and exit\n", CYAN, NC))
  log_sep("-", YELLOW)
}
exit_with_error <- function(err_msg) { log_error(err_msg); quit(status = 1, save = "no")}
validate_metadata <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  # ------- All four positional parameters are mandatory (SEQ_TYPE value may still be empty) ------- #
  if (length(args) < 4 || args[1] %in% c("-h", "--help")) { show_usage(); quit(status = 0, save = "no")}
  metadata_file  <- trimws(args[1])
  separator      <- args[2]
  seq_type_arg   <- trimws(args[3])
  quiet_arg      <- trimws(args[4])
  if (nchar(metadata_file) == 0) {exit_with_error("The METADATA_FILE parameter is mandatory and cannot be empty.")}
  if (nchar(trimws(separator)) == 0) {exit_with_error("The SEPARATOR parameter is mandatory and cannot be empty.")}
  quiet_clean <- tolower(quiet_arg)
  if (!quiet_clean %in% c("true", "false")) {
    log_error(sprintf("The QUIET parameter must be 'true' or 'false' (provided: '%s'). Defaulting to 'false' and continuing.", quiet_arg))
    QUIET <<- FALSE
  } else {
    QUIET <<- (quiet_clean == "true")
  }
  # ------- Check whether a valid SEQ_TYPE was passed (non-empty string and not literal "null") ------- #
  # ------- SEQ_TYPE is a mandatory positional argument, but its VALUE can be empty ------- #
  has_seq_type <- nchar(seq_type_arg) > 0 && tolower(seq_type_arg) != "null"
  seq_type <- if (has_seq_type) tolower(seq_type_arg) else NULL
  # ------- 1. Check if file exists ------- #
  if (!file.exists(metadata_file)) {exit_with_error(sprintf("Metadata file '%s' does not exist.", metadata_file))}
  # ------- 2. Check if file is empty ------- #
  file_lines <- readLines(metadata_file, warn = FALSE)
  if (length(file_lines) == 0) {exit_with_error("Metadata file is completely empty.")}
  # ------- 3. Validate separator on header ------- #
  header_line <- file_lines[1]
  if (!grepl(separator, header_line, fixed = TRUE)) {exit_with_error(sprintf("Specified separator '%s' was not found in the file header.", separator))}
  # ------- 4. Check for empty lines in raw file ------- #
  empty_line_indices <- which(trimws(file_lines) == "")
  if (length(empty_line_indices) > 0) {exit_with_error(sprintf("File contains %d empty line(s) at row(s): %s.", length(empty_line_indices), paste(empty_line_indices, collapse = ", ")))}
  # ------- Read metadata dataframe (keep NA strings intact using na.strings="") ------- #
  df <- tryCatch({
    read.table(
      file = metadata_file,
      header = TRUE,
      sep = separator,
      stringsAsFactors = FALSE,
      strip.white = TRUE,
      quote = "\"",
      check.names = FALSE,
      na.strings = ""
    )
  }, error = function(e) {exit_with_error(sprintf("Failed to parse metadata file: %s", e$message))})
  # ------- 5. Check expected columns ------- #
  expected_cols <- c("SampleName", "SampleFolder", "SampleNumber", "Batch", "Covariate", "VisName")
  missing_cols <- setdiff(expected_cols, colnames(df))
  if (length(missing_cols) > 0) {exit_with_error(sprintf("Missing expected column(s): %s", paste(missing_cols, collapse = ", ")))}
  # ------- 6. Check missing values in required columns ------- #
  strict_cols <- c("SampleName", "SampleNumber", "Covariate", "VisName")
  for (col in strict_cols) {
    missing_mask <- is.na(df[[col]]) | trimws(as.character(df[[col]])) == ""
    if (any(missing_mask)) {
      bad_rows <- which(missing_mask) + 1
      exit_with_error(sprintf("Column '%s' contains missing/empty values at row(s): %s.", col, paste(bad_rows, collapse = ", ")))
    }
  }
  # ------- 7. Check that rows sharing the same SampleNumber also share the same Batch, Covariate and VisName ------- #
  sample_groups <- split(df[, c("Batch", "Covariate", "VisName")],df[["SampleNumber"]])
  inconsistent_samples <- names(sample_groups)[vapply(sample_groups, function(x) {nrow(unique(x)) > 1}, logical(1))]
  if (length(inconsistent_samples) > 0) {exit_with_error(sprintf( "SampleNumber(s) associated with inconsistent Batch, Covariate or VisName values: %s.", paste(inconsistent_samples, collapse = ", ")))}
  # ------- 8. Check sequencing mode parameter (se / pe), when provided ------- #
  if (!is.null(seq_type)) {
    sample_counts <- table(df[["SampleNumber"]])
    if (seq_type == "se") {
      duplicated_samples <- names(sample_counts[sample_counts > 1])
      if (length(duplicated_samples) > 0) {
        exit_with_error(sprintf("Single-End (se) mode violation: sampleNumber(s) duplicated: %s.", paste(duplicated_samples, collapse = ", ")))}
    } else if (seq_type == "pe") {
      invalid_samples <- names(sample_counts[sample_counts != 2])
      if (length(invalid_samples) > 0) {
        exit_with_error(sprintf("Paired-End (pe) mode violation: sampleNumber(s) do not appear exactly twice: %s.", paste(invalid_samples, collapse = ", ")))}
    } else {
      exit_with_error(sprintf("Invalid SEQ_TYPE parameter '%s'. Supported values are 'se' or 'pe'.", seq_type))
    }
  } 
  log_success("Metadata validation passed successfully with no errors.")
  quit(status = 0, save = "no")
}  
validate_metadata()