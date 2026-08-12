#!/usr/bin/env Rscript

# ------- Script: extract_gene_mapping.R ------- #
# ------- Description: Extracts gene ID to gene Name and Biotype mapping from GTF/GFF3 files. ------- #
# ------- Supports both GTF (key "value") and GFF3 (key=value) attribute formats. ------- #

SCRIPT_NAME <- "extract_gene_mapping.R"
QUIET <- FALSE

CYAN <- "\033[0;36m"; YELLOW <- "\033[1;33m"; ORANGE <- "\033[0;33m"; GREEN <- "\033[0;32m"; RED <- "\033[0;31m"; NC <- "\033[0m"
log_info <- function(msg) { if (!exists("QUIET") || !isTRUE(QUIET)) cat(sprintf("%s[%s] [%s INFO]    %s%s\n", CYAN, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_step <- function(msg) { if (!exists("QUIET") || !isTRUE(QUIET)) cat(sprintf("%s[%s] [%s PROCESS] %s%s\n", YELLOW, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_warn <- function(msg) { if (!exists("QUIET") || !isTRUE(QUIET)) cat(sprintf("%s[%s] [%s WARNING] %s%s\n", ORANGE, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_success <- function(msg) { if (!exists("QUIET") || !isTRUE(QUIET)) cat(sprintf("%s[%s] [%s SUCCESS] %s%s\n", GREEN, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC)) }
log_sep <- function(char = "=", color = CYAN, ...) { if (!exists("QUIET") || !isTRUE(QUIET)) cat(sprintf("%s%s%s\n", color, paste(rep(char, 100), collapse = ""), NC)) }
log_error <- function(msg) { cat(sprintf("%s[%s] [%s ERROR]   %s%s\n", RED, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), SCRIPT_NAME, msg, NC), file = stderr()) }

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

# ------- Helper: escape regex metacharacters in a literal key ------- #
# Needed because attribute keys are interpolated directly into a PCRE pattern;
# without this, a key containing e.g. "." or "(" would silently break matching.
escape_regex <- function(x) {
  gsub("([.\\|()^{}+$*?\\[\\]])", "\\\\\\1", x, perl = TRUE)
}

# ------- Helper: count leading '#' comment lines without external tools ------- #
# Avoids relying on fread's ambiguous skip="string" behavior (it searches for the
# first occurrence of the substring anywhere in the file, not "lines starting with").
# Handles .gz transparently via gzfile().
count_header_lines <- function(file) {
  con <- if (grepl("\\.gz$", file, ignore.case = TRUE)) gzfile(file, "rt") else file(file, "rt")
  on.exit(close(con))
  n <- 0L
  repeat {
    line <- readLines(con, n = 1L, warn = FALSE)
    if (length(line) == 0L) break
    if (!startsWith(line, "#")) break
    n <- n + 1L
  }
  n
}

# ------- Helper: strip leading comment lines from a .gz file into a plain temp file ------- #
# fread() with a numeric `skip` on a .gz input requires the 'R.utils' package internally,
# which is not part of this image. We avoid that dependency by streaming the decompressed
# content (minus the header lines) to a plain-text temp file using base R connections only,
# then let fread() read that temp file with skip = 0.
decompress_skip_header <- function(gz_file, n_header, chunk_size = 100000L) {
  con_in <- gzfile(gz_file, "rt")
  on.exit(close(con_in), add = TRUE)
  if (n_header > 0) invisible(readLines(con_in, n = n_header, warn = FALSE))

  tmp <- tempfile(fileext = ".txt")
  con_out <- file(tmp, "wt")
  on.exit(close(con_out), add = TRUE)

  repeat {
    lines <- readLines(con_in, n = chunk_size, warn = FALSE)
    if (length(lines) == 0L) break
    writeLines(lines, con_out)
    if (length(lines) < chunk_size) break
  }

  tmp
}

# ------- Robust Attribute Extractor using Base R Regex ------- #
extract_attribute <- function(attr_strings, keys, is_gff3 = FALSE) {
  result <- rep(NA_character_, length(attr_strings))

  for (key in keys) {
    missing_idx <- which(is.na(result))
    if (length(missing_idx) == 0) break

    sub_attr <- attr_strings[missing_idx]
    safe_key <- escape_regex(key)

    if (is_gff3) {
      pattern <- paste0("(?:^|;)\\s*", safe_key, "=([^;]+)")
    } else {
      pattern <- paste0('(?:^|;)\\s*', safe_key, '\\s+"([^"]+)"')
    }

    # Usa regexec + regmatches di R base (PCRE = TRUE)
    m <- regexec(pattern, sub_attr, perl = TRUE)
    matches <- regmatches(sub_attr, m)

    extracted <- sapply(matches, function(x) {
      if (length(x) > 1) x[2] else NA_character_
    })

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

  if (length(args) < 3 || length(args) > 5) {
    show_usage()
    quit(status = 1)
  }

  annotation_file <- args[1]
  target_biotype  <- args[2]
  output_tsv      <- args[3]
  threads         <- if (length(args) >= 4) suppressWarnings(as.integer(args[4])) else 1L
  quiet_arg       <- if (length(args) >= 5) args[5] else "false"

  if (is.na(threads) || threads < 1) {
    threads <- 1L
  }

  if (tolower(quiet_arg) == "true") {
    assign("QUIET", TRUE, envir = .GlobalEnv)
  }

  if (!file.exists(annotation_file)) {
    log_error(paste("Input annotation file does not exist:", annotation_file))
    quit(status = 1)
  }

  # Il pacchetto data.table è installato a livello di sistema nell'immagine Docker
  # (r-cran-data.table via apt), quindi qui ci limitiamo a verificarne la presenza
  # invece di tentare un install.packages() che nel container non avrebbe senso.
  if (!requireNamespace("data.table", quietly = TRUE)) {
    log_error("Package 'data.table' is not available. It should be pre-installed in this image (r-cran-data.table).")
    quit(status = 1)
  }

  data.table::setDTthreads(threads)
  log_info(paste("Using", threads, "thread(s)"))
  log_info(paste("Processing annotation file:", annotation_file))

  # Detect file format (GTF vs GFF3)
  ext <- tolower(tools::file_ext(sub("\\.gz$", "", annotation_file)))
  is_gff3 <- ext %in% c("gff", "gff3")

  log_info(paste("Detected format:", ifelse(is_gff3, "GFF3", "GTF")))

  # Conta le righe di commento iniziali (##...) senza dipendere dal comportamento
  # ambiguo di skip="#" in fread, che cerca la prima occorrenza della sottostringa
  # nel file e non necessariamente le righe che iniziano con "#".
  n_header <- tryCatch(count_header_lines(annotation_file), error = function(e) 0L)
  log_info(paste("Skipping", n_header, "leading comment line(s)."))

  is_gz <- grepl("\\.gz$", annotation_file, ignore.case = TRUE)
  read_file <- annotation_file
  read_skip <- n_header
  tmp_file <- NULL

  if (is_gz) {
    # Questa versione di data.table richiede sempre il pacchetto 'R.utils' per leggere .gz
    # direttamente (non presente nell'immagine): decomprimiamo noi stessi in un file
    # temporaneo, già privo delle righe di commento iniziali.
    tmp_file <- tryCatch(decompress_skip_header(annotation_file, n_header), error = function(e) {
      log_error(paste("Failed to decompress annotation file:", e$message))
      quit(status = 1)
    })
    read_file <- tmp_file
    read_skip <- 0L
  }

  # Lettura veloce tramite fread delle colonne V3 (feature type) e V9 (attributes)
  dt <- tryCatch({
    data.table::fread(
      file = read_file,
      sep = "\t",
      header = FALSE,
      select = c(3, 9),
      col.names = c("feature", "attributes"),
      skip = read_skip,     # skip numerico esatto, non ambiguo come skip="#"
      quote = "",
      fill = TRUE,
      showProgress = FALSE
    )
  }, error = function(e) {
    log_error(paste("Failed to read annotation file with fread:", e$message))
    quit(status = 1)
  }, finally = {
    if (!is.null(tmp_file) && file.exists(tmp_file)) unlink(tmp_file)
  })

  if (nrow(dt) == 0) {
    log_error("Annotation file contains no valid data lines.")
    quit(status = 1)
  }

  log_info(paste("Parsed", nrow(dt), "feature lines."))

  # Filtraggio delle linee 'gene'
  gene_dt <- dt[tolower(feature) == "gene"]

  if (nrow(gene_dt) > 0) {
    attr_strings <- gene_dt$attributes
  } else {
    log_warn("No features of type 'gene' found. Parsing attributes across all records.")
    attr_strings <- dt$attributes
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

  res_dt <- data.table::data.table(
    gene_id      = gene_ids,
    gene_name    = gene_names,
    gene_biotype = biotypes
  )

  res_dt <- unique(res_dt[!is.na(gene_id) & gene_id != ""])

  log_info(paste("Extracted", nrow(res_dt), "unique gene entries."))

  if (tolower(target_biotype) != "all") {
    res_dt <- res_dt[tolower(gene_biotype) == tolower(target_biotype)]
    log_info(paste0("Filtering by biotype '", target_biotype, "': ", nrow(res_dt), " genes retained."))
  }

  if (nrow(res_dt) == 0) {
    log_warn("Warning: The resulting mapping table is empty after filtering!")
  }

  data.table::fwrite(res_dt, file = output_tsv, sep = "\t", quote = FALSE, row.names = FALSE, col.names = TRUE)
  log_success(paste0("Successfully saved mapping table to: ", output_tsv))
}

main()