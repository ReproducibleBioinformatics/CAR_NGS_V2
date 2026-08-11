#!/usr/bin/env Rscript

# ------- Script: extract_gene_mapping.R ------- #
# ------- Description: Extracts gene ID to gene Name and Biotype mapping from GTF/GFF3 files. ------- #
# ------- Supports both GTF (key "value") and GFF3 (key=value) attribute formats. ------- #

# ------- ANSI Color Codes for CLI Output ------- #
RED    <- "\033[0;31m"
GREEN  <- "\033[0;32m"
YELLOW <- "\033[0;33m"
BLUE   <- "\033[0;34m"
NC     <- "\033[0m" # No Color

# ------- Default Global Configuration ------- #
QUIET <- FALSE

log_info <- function(msg) {
  if (!QUIET) cat(paste0(BLUE, "[INFO] ", NC, msg, "\n"))
}

log_warn <- function(msg) {
  if (!QUIET) cat(paste0(YELLOW, "[WARN] ", NC, msg, "\n"))
}

log_error <- function(msg) {
  cat(paste0(RED, "[ERROR] ", NC, msg, "\n"), file = stderr())
}

show_usage <- function() {
  cat("Usage: Rscript extract_gene_mapping.R <annotation_file> <output_tsv> <target_biotype> [quiet]\n")
  cat("  <annotation_file> : Path to input GTF or GFF3 file (can be .gz)\n")
  cat("  <output_tsv>      : Path to save the extracted TSV mapping\n")
  cat("  <target_biotype>  : Biotype to filter (e.g., 'protein_coding') or 'all'\n")
  cat("  [quiet]           : Optional. Set to 'true' to suppress info logs\n")
}

# ------- Helper: URL Decode for GFF3 attributes ------- #
url_decode <- function(str) {
  if (is.na(str)) return(NA_character_)
  # ------- Decodes standard percent-encoding in GFF3 files (%20 = space, %3B = ;, %3D = =, etc.) ------- #
  utils::URLdecode(str)
}

# ------- Robust Attribute Extractor for GTF/GFF3 ------- #
extract_attribute <- function(attr_strings, keys, is_gff3 = FALSE) {
  # ------- Receives a vector of attribute strings and a prioritized list of keys to search ------- #
  result <- rep(NA_character_, length(attr_strings))
  
  for (key in keys) {
    # ------- Search only in elements where no value has been found yet ------- #
    missing_idx <- which(is.na(result))
    if (length(missing_idx) == 0) break
    
    sub_attr <- attr_strings[missing_idx]
    
    if (is_gff3) {
      # ------- GFF3 format: key=value; or key=value1,value2 ------- #
      pattern <- paste0("(?:^|;)\\s*", key, "=([^;]+)")
      matches <- stringi::stri_match_first_regex(sub_attr, pattern)
      extracted <- matches[, 2]
    } else {
      # ------- GTF format: key "value"; ------- #
      pattern <- paste0('(?:^|;)\\s*', key, '\\s+"([^"]+)"')
      matches <- stringi::stri_match_first_regex(sub_attr, pattern)
      extracted <- matches[, 2]
    }
    
    if (any(!is.na(extracted))) {
      # ------- Apply URL decode on extracted values for GFF3 ------- #
      if (is_gff3) {
        valid_extracted <- !is.na(extracted)
        extracted[valid_extracted] <- vapply(extracted[valid_extracted], url_decode, character(1), USE.NAMES = FALSE)
      }
      result[missing_idx] <- extracted
    }
  }
  
  return(result)
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  
  if (length(args) < 3 || length(args) > 4) {
    show_usage()
    quit(status = 1)
  }
  
  annotation_file <- args[1]
  output_tsv     <- args[2]
  target_biotype  <- args[3]
  
  if (length(args) == 4 && tolower(args[4]) == "true") {
    assign("QUIET", TRUE, envir = .GlobalEnv)
  }
  
  if (!file.exists(annotation_file)) {
    log_error(paste("Input annotation file does not exist:", annotation_file))
    quit(status = 1)
  }
  
  # ------- Check and install required package stringi if missing ------- #
  if (!requireNamespace("stringi", quietly = TRUE)) {
    log_info("Installing required package 'stringi'...")
    install.packages("stringi", repos = "https://cloud.r-project.org")
  }
  
  log_info(paste("Processing annotation file:", annotation_file))
  
  # ------- Detect file format (GTF vs GFF3) ------- #
  ext <- tolower(tools::file_ext(sub("\\.gz$", "", annotation_file)))
  is_gff3 <- ext %in% c("gff", "gff3")
  
  log_info(paste("Detected format:", ifelse(is_gff3, "GFF3", "GTF")))
  
  # ------- Load annotation file (handles both .gz and plain text) ------- #
  con <- if (endsWith(annotation_file, ".gz")) gzfile(annotation_file, "r") else file(annotation_file, "r")
  lines <- readLines(con)
  close(con)
  
  # ------- Filter out comment headers and empty lines ------- #
  lines <- lines[!startsWith(lines, "#") & nchar(trimws(lines)) > 0]
  
  if (length(lines) == 0) {
    log_error("Annotation file contains no valid data lines.")
    quit(status = 1)
  }
  
  log_info(paste("Parsing", length(lines), "feature lines..."))
  
  # ------- Split 9 standard GFF/GTF columns using stringi for efficiency ------- #
  split_cols <- stringi::stri_split_fixed(lines, "\t", n = 9)
  
  # ------- Discard malformed lines (< 9 columns) ------- #
  valid_lines <- sapply(split_cols, length) == 9
  if (!all(valid_lines)) {
    log_warn(paste("Skipping", sum(!valid_lines), "malformed lines."))
    split_cols <- split_cols[valid_lines]
  }
  
  feature_types <- sapply(split_cols, `[`, 3)
  attr_strings  <- sapply(split_cols, `[`, 9)
  
  # ------- Preferentially filter 'gene' feature lines to minimize redundancy ------- #
  gene_indices <- which(tolower(feature_types) == "gene")
  
  if (length(gene_indices) > 0) {
    attr_strings <- attr_strings[gene_indices]
  } else {
    log_warn("No features of type 'gene' found. Parsing attributes across all records.")
  }
  
  # ------- Define search key priorities based on file format ------- #
  if (is_gff3) {
    id_keys      <- c("ID", "gene_id", "Name")
    name_keys    <- c("Name", "gene_name", "ID", "symbol")
    biotype_keys <- c("gene_biotype", "gene_type", "biotype", "logic_name")
  } else {
    id_keys      <- c("gene_id")
    name_keys    <- c("gene_name", "gene_id")
    biotype_keys <- c("gene_biotype", "gene_type", "biotype")
  }
  
  # ------- Vectorized attribute extraction ------- #
  gene_ids   <- extract_attribute(attr_strings, id_keys, is_gff3 = is_gff3)
  gene_names <- extract_attribute(attr_strings, name_keys, is_gff3 = is_gff3)
  biotypes   <- extract_attribute(attr_strings, biotype_keys, is_gff3 = is_gff3)
  
  # ------- Remove 'gene:' prefix common in GFF3 files (e.g. Ensembl ID=gene:ENSG...) ------- #
  if (is_gff3 && any(!is.na(gene_ids))) {
    gene_ids <- sub("^gene:", "", gene_ids)
  }
  
  # ------- Fallback: use gene_id if gene_name is missing ------- #
  missing_names <- is.na(gene_names) | gene_names == ""
  gene_names[missing_names] <- gene_ids[missing_names]
  
  # ------- Fallback: assign 'unknown' if biotype is missing ------- #
  biotypes[is.na(biotypes) | biotypes == ""] <- "unknown"
  
  # ------- Construct data frame and remove duplicate entries ------- #
  df <- data.frame(
    gene_id   = gene_ids,
    gene_name = gene_names,
    biotype   = biotypes,
    stringsAsFactors = FALSE
  )
  
  # ------- Remove rows where gene_id is NA or empty ------- #
  df <- df[!is.na(df$gene_id) & df$gene_id != "", ]
  df <- unique(df)
  
  log_info(paste("Extracted", nrow(df), "unique gene entries."))
  
  # ------- Biotype filtering ------- #
  if (tolower(target_biotype) != "all") {
    df_filtered <- df[tolower(df$biotype) == tolower(target_biotype), ]
    log_info(paste0("Filtering by biotype '", target_biotype, "': ", nrow(df_filtered), " genes retained."))
    df <- df_filtered
  }
  
  if (nrow(df) == 0) {
    log_warn("Warning: The resulting mapping table is empty after filtering!")
  }
  
  # ------- Write result to output TSV file ------- #
  write.table(df, file = output_tsv, sep = "\t", quote = FALSE, row.names = FALSE, col.names = TRUE)
  log_info(paste0(GREEN, "Successfully saved mapping table to: ", output_tsv, NC))
}

main()