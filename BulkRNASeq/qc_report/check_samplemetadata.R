#!/usr/bin/env Rscript

NC <- "\033[0m"
CYAN <- "\033[0;36m"
YELLOW <- "\033[1;33m"
GREEN <- "\033[0;32m"
RED <- "\033[0;31m"

log_info <- function(msg) {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat(sprintf("%s[%s] [check_samplemetadata INFO]    %s%s\n", CYAN, timestamp, msg, NC))
}

log_step <- function(msg) {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat(sprintf("%s[%s] [check_samplemetadata PROCESS] %s%s\n", YELLOW, timestamp, msg, NC))
}

log_success <- function(msg) {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat(sprintf("%s[%s] [check_samplemetadata SUCCESS] %s%s\n", GREEN, timestamp, msg, NC))
}

log_error <- function(msg) {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat(sprintf("%s[%s] [check_samplemetadata ERROR]   %s%s\n", RED, timestamp, msg, NC), file = stderr())
}

log_sep <- function(char = "=", color = CYAN) {
  cat(sprintf("%s%s%s\n", color, paste(rep(char, 100), collapse = ""), NC))
}

show_usage <- function() {
  script_name <- basename(sub("--file=", "", commandArgs(trailingOnly = FALSE)[grep("--file=", commandArgs(trailingOnly = FALSE))]))
  if (length(script_name) == 0) script_name <- "validate_samplemetadata.R"
  
  log_sep("-", YELLOW)
  cat(sprintf("%sUsage:%s\n", YELLOW, NC))
  cat(sprintf("  Rscript %s <METADATA_FILE> <SEPARATOR> [SEQ_TYPE]\n\n", script_name))
  cat(sprintf("%sArguments:%s\n", YELLOW, NC))
  cat(sprintf("  %sMETADATA_FILE%s Path to the metadata CSV/TSV file (Required)\n", CYAN, NC))
  cat(sprintf("  %sSEPARATOR%s     Field separator used in file, e.g. ';' or ',' (Required)\n", CYAN, NC))
  cat(sprintf("  %sSEQ_TYPE%s      Optional mode: 'se' (Single-End) or 'pe' (Paired-End)\n\n", CYAN, NC))
  cat(sprintf("%sOptions:%s\n", YELLOW, NC))
  cat(sprintf("  %s-h, --help%s    Show this help message and exit\n", CYAN, NC))
  log_sep("-", YELLOW)
}

exit_with_error <- function(err_msg) {
  log_error(err_msg)
  log_sep()
  quit(status = 1, save = "no")
}

validate_metadata <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  
  if (length(args) < 2 || args[1] %in% c("-h", "--help")) {
    show_usage()
    quit(status = 0, save = "no")
  }
  
  metadata_file <- args[1]
  separator <- args[2]
  seq_type <- if (length(args) >= 3) tolower(args[3]) else NULL
  
  log_step("Validating input parameters and file existence...")
  
  # ------- 1. Check if file exists -------
  if (!file.exists(metadata_file)) {
    exit_with_error(sprintf("Metadata file '%s' does not exist.", metadata_file))
  }
  
  # ------- 2. Check if file is empty -------
  file_lines <- readLines(metadata_file, warn = FALSE)
  if (length(file_lines) == 0) {
    exit_with_error("Metadata file is completely empty.")
  }
  
  # ------- 3. Validate separator on header -------
  header_line <- file_lines[1]
  if (!grepl(separator, header_line, fixed = TRUE)) {
    exit_with_error(sprintf("Specified separator '%s' was not found in the file header.", separator))
  }
  
  # ------- 4. Check for empty lines in raw file -------
  empty_line_indices <- which(trimws(file_lines) == "")
  if (length(empty_line_indices) > 0) {
    exit_with_error(sprintf("File contains %d empty line(s) at row(s): %s.", 
                            length(empty_line_indices), 
                            paste(empty_line_indices, collapse = ", ")))
  }
  
  # ------- Read metadata dataframe (keep NA strings intact using na.strings="") -------
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
  }, error = function(e) {
    exit_with_error(sprintf("Failed to parse metadata file: %s", e$message))
  })
  
  # ------- 5. Check expected columns -------
  expected_cols <- c("SampleName", "SampleFolder", "sampleNumber", "Batch", "Covariate", "VisName")
  missing_cols <- setdiff(expected_cols, colnames(df))
  if (length(missing_cols) > 0) {
    exit_with_error(sprintf("Missing expected column(s): %s", paste(missing_cols, collapse = ", ")))
  }
  
  # ------- 6. Check missing values in required columns -------
  strict_cols <- c("SampleName", "sampleNumber", "Covariate", "VisName")
  for (col in strict_cols) {
    missing_mask <- is.na(df[[col]]) | trimws(as.character(df[[col]])) == ""
    if (any(missing_mask)) {
      bad_rows <- which(missing_mask) + 1  
      exit_with_error(sprintf("Column '%s' contains missing/empty values at row(s): %s.", 
                              col, paste(bad_rows, collapse = ", ")))
    }
  }

  # ------- Specific validation for Batch: allows text values, as well as NA, N/A (case-insensitive) -------
  batch_vals <- as.character(df[["Batch"]])
  batch_empty_mask <- is.na(batch_vals) | trimws(batch_vals) == ""
  batch_na_pattern_mask <- grepl("^(?i)(na|n/a)$", trimws(batch_vals))

  invalid_batch_rows <- which(batch_empty_mask & !batch_na_pattern_mask)
  if (length(invalid_batch_rows) > 0) {
    bad_rows <- invalid_batch_rows + 1
    exit_with_error(sprintf("Column 'Batch' contains invalid/empty values at row(s): %s.", 
                            paste(bad_rows, collapse = ", ")))
  }
  
  # ------- 7. Check optional sequencing mode parameter (se / pe) -------
  if (!is.null(seq_type)) {
    log_step(sprintf("Validating sampleNumber frequency for sequencing mode: '%s'...", seq_type))
    
    sample_counts <- table(df[["sampleNumber"]])
    
    if (seq_type == "se") {
      duplicated_samples <- names(sample_counts[sample_counts > 1])
      if (length(duplicated_samples) > 0) {
        exit_with_error(sprintf("Single-End (se) mode violation: sampleNumber(s) duplicated: %s.", 
                                paste(duplicated_samples, collapse = ", ")))
      }
    } else if (seq_type == "pe") {
      invalid_samples <- names(sample_counts[sample_counts != 2])
      if (length(invalid_samples) > 0) {
        exit_with_error(sprintf("Paired-End (pe) mode violation: sampleNumber(s) do not appear exactly twice: %s.", 
                                paste(invalid_samples, collapse = ", ")))
      }
    } else {
      exit_with_error(sprintf("Invalid SEQ_TYPE parameter '%s'. Supported values are 'se' or 'pe'.", seq_type))
    }
  }
  log_success("Metadata validation passed successfully with no errors.")
  quit(status = 0, save = "no")
}

validate_metadata()