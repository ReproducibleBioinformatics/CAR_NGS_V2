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
  cat("Usage: Rscript extract_gene_mapping.R <annotation_file> <target_biotype> <output_tsv> [threads] [quiet]\n")
  cat("  <annotation_file> : Path to input GTF or GFF3 file (can be .gz)\n")
  cat("  <target_biotype>  : Biotype to filter (e.g., 'protein_coding') or 'all'\n")
  cat("  <output_tsv>      : Path to save the extracted TSV mapping\n")
  cat("  [threads]         : Optional. Number of threads to use (default: 1)\n")
  cat("  [quiet]           : Optional. Set to 'true' to suppress info logs\n")
}

# ------- Helper: URL Decode for GFF3 attributes ------- #
url_decode <- function(str) {
  if (is.na(str)) return(NA_character_)
  utils::URLdecode(str)
}

# ------- Robust Attribute Extractor for GTF/GFF3 ------- #
extract_attribute <- function(attr_strings, keys, is_gff3 = FALSE) {
  result <- rep(NA_character_, length(attr_strings))
  
  for (key in keys) {
    missing_idx <- which(is.na(result))
    if (length(missing_idx) == 0) break
    
    sub_attr <- attr_strings[missing_idx]
    
    if (is_gff3) {
      pattern <- paste0("(?:^|;)\\s*", key, "=([^;]+)")
      matches <- stringi::stri_match_first_regex(sub_attr, pattern)
      extracted <- matches[, 2]
    } else {
      pattern <- paste0('(?:^|;)\\s*', key, '\\s+"([^"]+)"')
      matches <- stringi::stri_match_first_regex(sub_attr, pattern)
      extracted <- matches[, 2]
    }
    
    if (any(!is.na(extracted))) {
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
  
  # Accetta da 3 a 5 argomenti
  if (length(args) < 3 || length(args) > 5) {
    show_usage()
    quit(status = 1)
  }
  
  # Allineamento parametri con lo script Bash
  annotation_file <- args[1]
  target_biotype  <- args[2]
  output_tsv      <- args[3]
  threads         <- if (length(args) >= 4) as.integer(args[4]) else 1
  quiet_arg       <- if (length(args) >= 5) args[5] else "false"
  
  if (is.na(threads) || threads < 1) {
    threads <- 1
  }

  if (tolower(quiet_arg) == "true") {
    assign("QUIET", TRUE, envir = .GlobalEnv)
  }
  
  if (!file.exists(annotation_file)) {
    log_error(paste("Input annotation file does not exist:", annotation_file))
    quit(status = 1)
  }
  
  # Check e caricamento dei pacchetti richiesti
  if (!requireNamespace("stringi", quietly = TRUE)) {
    log_info("Installing required package 'stringi'...")
    install.packages("stringi", repos = "https://cloud.r-project.org")
  }
  if (!requireNamespace("data.table", quietly = TRUE)) {
    log_info("Installing required package 'data.table'...")
    install.packages("data.table", repos = "https://cloud.r-project.org")
  }
  
  # Impostazione del multithreading per le operazioni compatibili
  data.table::setDTthreads(threads)
  log_info(paste("Using", threads, "thread(s)"))
  log_info(paste("Processing annotation file:", annotation_file))
  
  # Detect file format (GTF vs GFF3)
  ext <- tolower(tools::file_ext(sub("\\.gz$", "", annotation_file)))
  is_gff3 <- ext %in% c("gff", "gff3")
  
  log_info(paste("Detected format:", ifelse(is_gff3, "GFF3", "GTF")))
  
  # Load annotation file
  con <- if (endsWith(annotation_file, ".gz")) gzfile(annotation_file, "r") else file(annotation_file, "r")
  lines <- readLines(con)
  close(con)
  
  lines <- lines[!startsWith(lines, "#") & nchar(trimws(lines)) > 0]
  
  if (length(lines) == 0) {
    log_error("Annotation file contains no valid data lines.")
    quit(status = 1)
  }
  
  log_info(paste("Parsing", length(lines), "feature lines..."))
  
  split_cols <- stringi::stri_split_fixed(lines, "\t", n = 9)
  
  valid_lines <- sapply(split_cols, length) == 9
  if (!all(valid_lines)) {
    log_warn(paste("Skipping", sum(!valid_lines), "malformed lines."))
    split_cols <- split_cols[valid_lines]
  }
  
  feature_types <- sapply(split_cols, `[`, 3)
  attr_strings  <- sapply(split_cols, `[`, 9)
  
  gene_indices <- which(tolower(feature_types) == "gene")
  
  if (length(gene_indices) > 0) {
    attr_strings <- attr_strings[gene_indices]
  } else {
    log_warn("No features of type 'gene' found. Parsing attributes across all records.")
  }
  
  if (is_gff3) {
    id_keys      <- c("ID", "gene_id", "Name")
    name_keys    <- c("Name", "gene_name", "ID", "symbol")
    biotype_keys <- c("gene_biotype", "gene_type", "biotype", "logic_name")
  } else {
    id_keys      <- c("gene_id")
    name_keys    <- c("gene_name", "gene_id")
    biotype_keys <- c("gene_biotype", "gene_type", "biotype")
  }
  
  gene_ids   <- extract_attribute(attr_strings, id_keys, is_gff3 = is_gff3)
  gene_names <- extract_attribute(attr_strings, name_keys, is_gff3 = is_gff3)
  biotypes   <- extract_attribute(attr_strings, biotype_keys, is_gff3 = is_gff3)
  
  if (is_gff3 && any(!is.na(gene_ids))) {
    gene_ids <- sub("^gene:", "", gene_ids)
  }
  
  missing_names <- is.na(gene_names) | gene_names == ""
  gene_names[missing_names] <- gene_ids[missing_names]
  
  biotypes[is.na(biotypes) | biotypes == ""] <- "unknown"
  
  df <- data.frame(
    gene_id   = gene_ids,
    gene_name = gene_names,
    biotype   = biotypes,
    stringsAsFactors = FALSE
  )
  
  df <- df[!is.na(df$gene_id) & df$gene_id != "", ]
  df <- unique(df)
  
  log_info(paste("Extracted", nrow(df), "unique gene entries."))
  
  if (tolower(target_biotype) != "all") {
    df_filtered <- df[tolower(df$biotype) == tolower(target_biotype), ]
    log_info(paste0("Filtering by biotype '", target_biotype, "': ", nrow(df_filtered), " genes retained."))
    df <- df_filtered
  }
  
  if (nrow(df) == 0) {
    log_warn("Warning: The resulting mapping table is empty after filtering!")
  }
  
  write.table(df, file = output_tsv, sep = "\t", quote = FALSE, row.names = FALSE, col.names = TRUE)
  log_info(paste0(GREEN, "Successfully saved mapping table to: ", output_tsv, NC))
}

main()