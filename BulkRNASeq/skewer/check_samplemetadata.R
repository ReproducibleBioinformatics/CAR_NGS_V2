#!/usr/bin/env Rscript

NC <- "\033[0m"
CYAN <- "\033[0;36m"
YELLOW <- "\033[1;33m"
GREEN <- "\033[0;32m"
RED <- "\033[0;31m"
ORANGE <- "\033[0;33m"

QUIET <- "false"

log_info <- function(msg) {
  if (QUIET == "true") return()
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat(sprintf("%s[%s] [check_samplemetadata INFO]    %s%s\n", CYAN, timestamp, msg, NC))
}

log_step <- function(msg) {
  if (QUIET == "true") return()
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat(sprintf("%s[%s] [check_samplemetadata PROCESS] %s%s\n", YELLOW, timestamp, msg, NC))
}

log_warn <- function(msg) {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat(sprintf("%s[%s] [check_samplemetadata WARNING] %s%s\n", ORANGE, timestamp, msg, NC))
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
  if (length(script_name) == 0) script_name <- "check_samplemetadata.R"
  
  log_sep("-", YELLOW)
  cat(sprintf("%sUsage:%s\n", YELLOW, NC))
  cat(sprintf("  Rscript %s <METADATA_FILE> <SEPARATOR> <SEQ_TYPE> <QUIET>\n\n", script_name))
  cat(sprintf("%sArguments (all mandatory):%s\n", YELLOW, NC))
  cat(sprintf("  %sMETADATA_FILE%s Path to the metadata CSV/TSV file\n", CYAN, NC))
  cat(sprintf("  %sSEPARATOR%s     Field separator used in file (e.g. ';' or ',' or 'tab')\n", CYAN, NC))
  cat(sprintf("  %sSEQ_TYPE%s      Sequencing mode: 'se' or 'pe' (Pass '', 'none', or 'null' to ignore frequency check)\n", CYAN, NC))
  cat(sprintf("  %sQUIET%s         Suppress log messages: 'true' or 'false'\n\n", CYAN, NC))
  cat(sprintf("%sOptions:%s\n", YELLOW, NC))
  cat(sprintf("  %s-h, --help%s    Show this help message and exit\n", CYAN, NC))
  log_sep("-", YELLOW)
}

exit_with_error <- function(err_msg) {
  log_error(err_msg)
  log_sep()
  quit(status = 1, save = "no")
}

parse_separator <- function(sep_input) {
  sep_clean <- tolower(trimws(sep_input))
  if (sep_clean %in% c("tab", "\t", "\\t")) {
    return("\t")
  } else if (sep_clean %in% c(",", ";")) {
    return(sep_clean)
  } else {
    return(sep_input)
  }
}

validate_metadata <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  
  # Controlla la presenza esatta dei 4 parametri obbligatori
  if (length(args) < 4 || args[1] %in% c("-h", "--help")) {
    show_usage()
    quit(status = if (length(args) >= 1 && args[1] %in% c("-h", "--help")) 0 else 1, save = "no")
  }
  
  metadata_file <- args[1]
  separator <- parse_separator(args[2])
  
  raw_seq_type <- tolower(trimws(args[3]))
  seq_type <- if (raw_seq_type %in% c("se", "pe")) raw_seq_type else NULL
  
  quiet_val <- tolower(trimws(args[4]))
  if (quiet_val %in% c("true", "false")) {
    QUIET <<- quiet_val
  } else {
    exit_with_error(sprintf("Invalid QUIET parameter '%s'. Must be 'true' or 'false'.", args[4]))
  }

  log_sep("=", CYAN)
  log_info("Metadata Validation Context:")
  cat(sprintf("  %sMetadata File   :%s %s%s%s\n", CYAN, NC, YELLOW, metadata_file, NC))
  cat(sprintf("  %sSeparator       :%s '%s%s%s'\n", CYAN, NC, YELLOW, if (separator == "\t") "\\t" else separator, NC))
  cat(sprintf("  %sSeq Type        :%s %s%s%s\n", CYAN, NC, YELLOW, ifelse(is.null(seq_type), sprintf("%s (ignored)", raw_seq_type), seq_type), NC))
  cat(sprintf("  %sQuiet Parameter :%s %s%s%s\n", CYAN, NC, YELLOW, QUIET, NC))
  log_sep("=", CYAN)

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
    exit_with_error(sprintf("Specified separator '%s' was not found in the file header.", if (separator == "\t") "\\t" else separator))
  }
  
  # ------- 4. Check for empty lines in raw file -------
  empty_line_indices <- which(trimws(file_lines) == "")
  if (length(empty_line_indices) > 0) {
    exit_with_error(sprintf("File contains %d empty line(s) at row(s): %s.", 
                            length(empty_line_indices), 
                            paste(empty_line_indices, collapse = ", ")))
  }
  
  # ------- Read metadata dataframe -------
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
  expected_cols <- c("SampleName", "SampleFolder", "SampleNumber", "Batch", "Covariate", "VisName")
  missing_cols <- setdiff(expected_cols, colnames(df))
  if (length(missing_cols) > 0) {
    exit_with_error(sprintf("Missing expected column(s): %s", paste(missing_cols, collapse = ", ")))
  }
  
  # ------- 6. Check missing values in required columns -------
  strict_cols <- c("SampleName", "SampleNumber", "Covariate", "VisName")
  for (col in strict_cols) {
    missing_mask <- is.na(df[[col]]) | trimws(as.character(df[[col]])) == ""
    if (any(missing_mask)) {
      bad_rows <- which(missing_mask) + 1  
      exit_with_error(sprintf("Column '%s' contains missing/empty values at row(s): %s.", 
                              col, paste(bad_rows, collapse = ", ")))
    }
  }

  # ------- Specific validation for Batch -------
  batch_vals <- as.character(df[["Batch"]])
  batch_empty_mask <- is.na(batch_vals) | trimws(batch_vals) == ""
  batch_na_pattern_mask <- grepl("^(?i)(na|n/a)$", trimws(batch_vals))

  invalid_batch_rows <- which(batch_empty_mask & !batch_na_pattern_mask)
  if (length(invalid_batch_rows) > 0) {
    bad_rows <- invalid_batch_rows + 1
    exit_with_error(sprintf("Column 'Batch' contains invalid/empty values at row(s): %s.", 
                            paste(bad_rows, collapse = ", ")))
  }
  
  # ------- 7. Check sequencing mode parameter (se / pe) -------
  if (!is.null(seq_type)) {
    log_step(sprintf("Validating SampleNumber frequency for sequencing mode: '%s'...", seq_type))
    
    sample_counts <- table(df[["SampleNumber"]])
    
    if (seq_type == "se") {
      duplicated_samples <- names(sample_counts[sample_counts > 1])
      if (length(duplicated_samples) > 0) {
        exit_with_error(sprintf("Single-End (se) mode violation: SampleNumber(s) duplicated: %s.", 
                                paste(duplicated_samples, collapse = ", ")))
      }
    } else if (seq_type == "pe") {
      invalid_samples <- names(sample_counts[sample_counts != 2])
      if (length(invalid_samples) > 0) {
        exit_with_error(sprintf("Paired-End (pe) mode violation: SampleNumber(s) do not appear exactly twice: %s.", 
                                paste(invalid_samples, collapse = ", ")))
      }
    }
  } else {
    log_info("Skipping SampleNumber frequency check (SEQ_TYPE is not 'se' or 'pe').")
  }

  log_sep()
  log_success("Metadata validation passed successfully with no errors.")
  quit(status = 0, save = "no")
}

validate_metadata()