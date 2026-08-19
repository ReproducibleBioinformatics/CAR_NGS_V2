#!/usr/bin/env Rscript
suppressMessages(library(data.table))
SCRIPT_NAME <- "generate_expression_tables.R"
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
  cat(paste0(YELLOW, "Usage:", NC, "\n"))
  cat(paste0("  Rscript ", SCRIPT_NAME, " <metadata> <metadata_sep> <input_dir> <results> <bio_type> <mapping_tsv> <threads> <quiet>\n\n"))
  cat(paste0(YELLOW, "Arguments (all mandatory):", NC, "\n"))
  cat(paste0("  ", CYAN, "metadata", NC, "       Path to the metadata file containing sample names\n"))
  cat(paste0("  ", CYAN, "metadata_sep", NC, "   Field separator used in metadata (e.g., ';', ',', 'tab')\n"))
  cat(paste0("  ", CYAN, "input_dir", NC, "      Base directory containing RSEM result files\n"))
  cat(paste0("  ", CYAN, "results", NC, "        Output directory for compiled expression tables\n"))
  cat(paste0("  ", CYAN, "bio_type", NC, "       Target biotype filter or 'all' to skip filtering\n"))
  cat(paste0("  ", CYAN, "mapping_tsv", NC, "    3-column gene mapping file (gene_id, gene_name, gene_biotype)\n"))
  cat(paste0("  ", CYAN, "threads", NC, "        Number of parallel threads (positive integer)\n"))
  cat(paste0("  ", CYAN, "quiet", NC, "          Suppress processing log messages: 'true' or 'false'\n"))
  log_sep("-", YELLOW)
}
parse_separator_inplace <- function(sep_str) {
  sep_clean <- tolower(trimws(sep_str))
  if (sep_clean %in% c("tab", "\t", "\\t")) {
    return("\t")
  } else if (sep_clean %in% c(",", ";")) {
    return(sep_clean)
  } else {
    return(NULL)
  }
}
main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
# ------- Argument Checking and Assignment ------- #
  if (length(args) != 8 || args[1] %in% c("-h", "--help")) {show_usage(); quit(status = 1)}
  metadata_file <- args[1]
  metadata_sep  <- args[2]
  input_dir     <- args[3]
  results       <- args[4]
  bio_type_arg  <- args[5]
  mapping_file  <- args[6]
  threads_arg   <- args[7]
  quiet_arg     <- args[8]
  quiet_clean <- tolower(quiet_arg)
  if (!quiet_clean %in% c("true", "false")) {log_error(sprintf("The QUIET parameter must be 'true' or 'false' (provided: '%s'). Defaulting to 'false' and continuing.", quiet_arg));
  } else if (quiet_clean == "true") { assign("QUIET", TRUE, envir = .GlobalEnv) }
  # ------- Validate and Normalize Metadata Separator ------- #
  parsed_sep <- parse_separator_inplace(metadata_sep)
  if (is.null(parsed_sep)) {log_error(paste0("Invalid metadata separator provided: '", metadata_sep, "'. Allowed values: ',', ';', '\\t', 'tab'.")); quit(status = 1)}
  # ------- Validate Threads Parameter ------- #
  threads_num <- suppressWarnings(as.integer(threads_arg))
  if (is.na(threads_num) || threads_num <= 0) {log_error(paste0("The threads parameter must be a positive integer (provided: '", threads_arg, "')")); quit(status = 1); }
  setDTthreads(threads_num)
  # ------- Check Results Directory ------- #
  if (!dir.exists(results)) {log_error(paste0("Results directory '", results, "' does not exist.")); quit(status = 1)}
  # ------- Check Input Directory ------- #
  if (!dir.exists(input_dir)) { log_error(paste0("Input directory '", input_dir, "' does not exist.")); quit(status = 1)}
  # ------- Check Metadata File ------- #
  if (!file.exists(metadata_file)) {log_error(paste0("Sample metadata file '", metadata_file, "' does not exist.")); quit(status = 1)}
  # ------- Check Mapping File ------- #
  if (!file.exists(mapping_file)) {log_error(paste0("Mapping file '", mapping_file, "' does not exist.")); quit(status = 1)}
  output_prefix <- paste(results, "experiment", sep = "/")
  # ------- Read Metadata File ------- #
  metadata <- tryCatch({
    fread(metadata_file, sep = parsed_sep, header = TRUE)
  }, error = function(e) {
    log_error(paste0("Failed to read metadata file '", metadata_file, "': ", e$message))
    quit(status = 2)
  })
  col_names <- colnames(metadata)
  samplename_col <- col_names[tolower(col_names) %in% c("samplename", "sample_name", "sample")][1]
  if (length(samplename_col) == 0 || is.na(samplename_col)) {
    log_error("Column 'SampleName' (or 'sample_name' / 'sample') not found in metadata file.")
    quit(status = 1)
  }
  visname_col   <- col_names[tolower(col_names) %in% c("visname", "sampleid", "id")][1]
  covariate_col <- col_names[tolower(col_names) %in% c("covariate", "condition", "group")][1]
  batch_col     <- col_names[tolower(col_names) %in% c("batch")][1]
  if (nrow(metadata) < 2) {log_error("The experimental metadata contains fewer than 2 unique samples."); quit(status = 1)}
  vis_vals <- if (!is.na(visname_col)) metadata[[visname_col]] else metadata[[samplename_col]]
  cov_vals <- if (!is.na(covariate_col)) metadata[[covariate_col]] else NULL
  ls.names <- vis_vals
  if (!is.null(cov_vals)) {
    ls.names <- paste(ls.names, cov_vals, sep = "_")
  }
  if (!is.na(batch_col)) {
    batch_vals <- metadata[[batch_col]]
    valid_batches <- !is.na(batch_vals) & batch_vals != "NA" & batch_vals != ""
    ls.names <- ifelse(valid_batches, paste(ls.names, batch_vals, sep = "_"), ls.names)
  }
  # ------- Core Step 1: Scan RSEM Files ------- #
  gene_files <- c()
  iso_files  <- c()
  for (i in seq_len(nrow(metadata))) {
    sample_raw_name <- metadata[[samplename_col]][i]
    g_filename <- if (endsWith(sample_raw_name, ".genes.results")) sample_raw_name else paste0(sample_raw_name, ".genes.results")
    g_path     <- file.path(input_dir, g_filename)
    i_filename <- sub("\\.genes\\.results$", ".isoforms.results", sample_raw_name)
    if (!endsWith(i_filename, ".isoforms.results")) i_filename <- paste0(i_filename, ".isoforms.results")
    i_path     <- file.path(input_dir, i_filename)
    if (!file.exists(g_path)) {
      log_error(paste0("RSEM gene file '", g_path, "' does not exist."))
      quit(status = 2)
    }
    if (!file.exists(i_path)) {
      log_error(paste0("RSEM isoform file '", i_path, "' does not exist."))
      quit(status = 2)
    }
    gene_files[i] <- g_path
    iso_files[i]  <- i_path
  }
  all_rsem_genes <- unique(unlist(lapply(gene_files, function(f) fread(f, select = "gene_id", header = TRUE)$gene_id)))
  all_rsem_isos  <- unique(unlist(lapply(iso_files,  function(f) fread(f, select = "transcript_id", header = TRUE)$transcript_id)))
  log_info(paste0("Found ", length(all_rsem_genes), " unique genes and ", length(all_rsem_isos), " unique isoforms across samples."))
  # ------- Core Step 2: Annotate Genes ------- #
  map_dt <- fread(mapping_file, sep = "\t", header = TRUE)
  setkey(map_dt, gene_id)
  rsem_map <- data.table(gene_id = all_rsem_genes)
  rsem_map <- map_dt[rsem_map, on = "gene_id"]
  rsem_map[is.na(gene_name) | gene_name == "", gene_name := gene_id]
  rsem_map[is.na(gene_biotype), gene_biotype := "unknown"]
  if (tolower(bio_type_arg) != "all") {
    rsem_map <- rsem_map[gene_biotype == bio_type_arg]
    log_info(paste0("Biotype filter applied ('", bio_type_arg, "'): ", nrow(rsem_map), " genes retained out of ", length(all_rsem_genes), "."))
  }
  rsem_map[, gene_key := paste0(gene_id, ":", gene_name)]
  ref_gene_ids  <- rsem_map$gene_id
  ref_gene_keys <- rsem_map$gene_key
  ref_iso_ids   <- all_rsem_isos
  # ------- Core Step 3: Gene-Level Extraction ------- #
  counts_list <- list()
  fpkm_list   <- list()
  tpm_list    <- list()
  total_gene_anomalies <- 0
  for (i in seq_len(nrow(metadata))) {
    col_label <- ls.names[i]
    dt_genes  <- fread(gene_files[i], sep = "\t", header = TRUE)
    idx <- match(ref_gene_ids, dt_genes$gene_id)
    missing_genes <- sum(is.na(idx))
    if (missing_genes > 0) {
      log_warn(paste0("ANOMALY: Sample '", col_label, "' is missing ", missing_genes, " genes. Imputing with 0."))
      total_gene_anomalies <- total_gene_anomalies + missing_genes
    }
    c_vec <- round(as.numeric(dt_genes$expected_count[idx])); c_vec[is.na(c_vec)] <- 0
    f_vec <- dt_genes$FPKM[idx]; f_vec[is.na(f_vec)] <- 0
    t_vec <- dt_genes$TPM[idx];  t_vec[is.na(t_vec)] <- 0
    counts_list[[col_label]] <- c_vec
    fpkm_list[[col_label]]   <- f_vec
    tpm_list[[col_label]]    <- t_vec
  }
  dt_counts <- as.data.table(counts_list)
  dt_fpkm   <- as.data.table(fpkm_list)
  dt_tpm    <- as.data.table(tpm_list)
  # ------- Core Step 4: Isoform-Level Extraction ------- #
  counts_iso_list <- list()
  fpkm_iso_list   <- list()
  tpm_iso_list    <- list()
  total_iso_anomalies <- 0
  for (i in seq_len(nrow(metadata))) {
    col_label <- ls.names[i]
    dt_iso    <- fread(iso_files[i], sep = "\t", header = TRUE)
    idx_iso <- match(ref_iso_ids, dt_iso$transcript_id)
    missing_isos <- sum(is.na(idx_iso))
    if (missing_isos > 0) {log_warn(paste0("ANOMALY: Sample '", col_label, "' is missing ", missing_isos, " isoforms. Imputing with 0.")); total_iso_anomalies <- total_iso_anomalies + missing_isos }
    c_iso_vec <- round(as.numeric(dt_iso$expected_count[idx_iso])); c_iso_vec[is.na(c_iso_vec)] <- 0
    f_iso_vec <- dt_iso$FPKM[idx_iso]; f_iso_vec[is.na(f_iso_vec)] <- 0
    t_iso_vec <- dt_iso$TPM[idx_iso];  t_iso_vec[is.na(t_iso_vec)] <- 0
    counts_iso_list[[col_label]] <- c_iso_vec
    fpkm_iso_list[[col_label]]   <- f_iso_vec
    tpm_iso_list[[col_label]]    <- t_iso_vec
  }
  dt_counts_iso <- as.data.table(counts_iso_list)
  dt_fpkm_iso   <- as.data.table(fpkm_iso_list)
  dt_tpm_iso    <- as.data.table(tpm_iso_list)
  # ------- Core Step 5: Export Matrices and Metadata ------- #
  tryCatch({
    final_counts <- cbind(gene_id = ref_gene_keys, dt_counts)
    final_fpkm   <- cbind(gene_id = ref_gene_keys, dt_fpkm)
    final_tpm    <- cbind(gene_id = ref_gene_keys, dt_tpm)
    final_counts_iso <- cbind(transcript_id = ref_iso_ids, dt_counts_iso)
    final_fpkm_iso   <- cbind(transcript_id = ref_iso_ids, dt_fpkm_iso)
    final_tpm_iso    <- cbind(transcript_id = ref_iso_ids, dt_tpm_iso)
    counts     <- as.data.frame(dt_counts)
    fpkm       <- as.data.frame(dt_fpkm)
    tpm        <- as.data.frame(dt_tpm)
    counts.iso <- as.data.frame(dt_counts_iso)
    fpkm.iso   <- as.data.frame(dt_fpkm_iso)
    tpm.iso    <- as.data.frame(dt_tpm_iso)
    rownames(counts)     <- ref_gene_keys
    rownames(fpkm)       <- ref_gene_keys
    rownames(tpm)        <- ref_gene_keys
    rownames(counts.iso) <- ref_iso_ids
    rownames(fpkm.iso)   <- ref_iso_ids
    rownames(tpm.iso)    <- ref_iso_ids
    save(counts, fpkm, tpm, counts.iso, fpkm.iso, tpm.iso, file = paste0(output_prefix, "_experiment.tables.Rda"))
    fwrite(final_counts, file = paste0(output_prefix, "_counts.txt"), sep = "\t", col.names = TRUE, quote = FALSE)
    final_fpkm_log <- cbind(gene_id = ref_gene_keys, log2(dt_fpkm + 1))
    fwrite(final_fpkm_log, file = paste0(output_prefix, "_log2FPKM.txt"), sep = "\t", col.names = TRUE, quote = FALSE)
    final_tpm_log <- cbind(gene_id = ref_gene_keys, log2(dt_tpm + 1))
    fwrite(final_tpm_log, file = paste0(output_prefix, "_log2TPM.txt"), sep = "\t", col.names = TRUE, quote = FALSE)
    fwrite(final_counts_iso, file = paste0(output_prefix, "_isoforms_counts.txt"), sep = "\t", col.names = TRUE, quote = FALSE)
    final_fpkm_iso_log <- cbind(transcript_id = ref_iso_ids, log2(dt_fpkm_iso + 1))
    fwrite(final_fpkm_iso_log, file = paste0(output_prefix, "_isoforms_log2FPKM.txt"), sep = "\t", col.names = TRUE, quote = FALSE)
    final_tpm_iso_log <- cbind(transcript_id = ref_iso_ids, log2(dt_tpm_iso + 1))
    fwrite(final_tpm_iso_log, file = paste0(output_prefix, "_isoforms_log2TPM.txt"), sep = "\t", col.names = TRUE, quote = FALSE)
    # ------- Export Updated Metadata ------- #
    updated_metadata <- copy(metadata)
    updated_metadata[[samplename_col]] <- ls.names
    orig_filename <- basename(metadata_file)
    ext <- tools::file_ext(orig_filename)
    base_name <- tools::file_path_sans_ext(orig_filename)
    if (grepl("_", base_name)) {
      new_base <- sub("_[^_]+$", "_annotation", base_name)
      out_filename <- paste0(new_base, ".", ext)
    } else {
      out_filename <- paste0(base_name, "_annotation.", ext)
    }
    metadata_out_path <- file.path(results, out_filename)
    fwrite(updated_metadata, file = metadata_out_path, sep = parsed_sep, col.names = TRUE, quote = FALSE)
    log_info(paste0("Updated metadata written to: ", metadata_out_path))
  }, error = function(e) {
    log_error(paste0("Error occurred while saving compiled matrices/metadata: ", e$message))
    quit(status = 2)
  })
  # ------- Processing Summary Output ------- #
  if (!QUIET) {
    cat("\n===== QUANTIFICATION COMPILATION SUMMARY =====\n")
    cat(paste0("Metadata file:                 ", metadata_file, "\n"))
    cat(paste0("Metadata delimiter:            '", metadata_sep, "'\n"))
    cat(paste0("Mapping File:                  ", mapping_file, "\n"))
    cat(paste0("Selected filtering biotype:    ", bio_type_arg, "\n"))
    cat(paste0("Total unique samples processed:", nrow(metadata), "\n"))
    cat(paste0("Compiled genes entries count:  ", length(ref_gene_keys), "\n"))
    cat(paste0("Compiled isoforms count:       ", length(ref_iso_ids), "\n"))
    cat(paste0("Updated Metadata output:       ", metadata_out_path, "\n"))
    if (total_gene_anomalies > 0 || total_iso_anomalies > 0) {
      cat(paste0(RED, "TOTAL ANOMALIES DETECTED:      Genes(", total_gene_anomalies, ") Isoforms(", total_iso_anomalies, ")", NC, "\n"))
    } else {
      cat(paste0(GREEN, "Matrix alignment is perfect. No anomalies detected.", NC, "\n"))
    }
    cat("==============================================\n\n")
  }
}

main()