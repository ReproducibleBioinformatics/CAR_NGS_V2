#!/usr/bin/env Rscript

# ------- Logger and Formatting Setup ------- #
SCRIPT_NAME <- "filter_chromosomes.R"

# ANSI color codes for execution logging
CYAN   <- "\033[0;36m"
YELLOW <- "\033[1;33m"
ORANGE <- "\033[0;33m"
GREEN  <- "\033[0;32m"
RED    <- "\033[0;31m"
NC     <- "\033[0m"

get_timestamp <- function() {
    format(Sys.time(), "%Y-%m-%d %H:%M:%S")
}

log_info <- function(msg) {
    if (exists("QUIET") && QUIET == "true") return(invisible(NULL))
    cat(sprintf("%s[%s] [%s INFO]    %s%s\n", CYAN, get_timestamp(), SCRIPT_NAME, msg, NC))
}

log_step <- function(msg) {
    if (exists("QUIET") && QUIET == "true") return(invisible(NULL))
    cat(sprintf("%s[%s] [%s PROCESS] %s%s\n", YELLOW, get_timestamp(), SCRIPT_NAME, msg, NC))
}

log_warn <- function(msg) {
    cat(sprintf("%s[%s] [%s WARNING] %s%s\n", ORANGE, get_timestamp(), SCRIPT_NAME, msg, NC))
}

log_success <- function(msg) {
    cat(sprintf("%s[%s] [%s SUCCESS] %s%s\n", GREEN, get_timestamp(), SCRIPT_NAME, msg, NC))
}

log_error <- function(msg) {
    cat(sprintf("%s[%s] [%s ERROR]   %s%s\n", RED, get_timestamp(), SCRIPT_NAME, msg, NC), file = stderr())
}

log_sep <- function(char = "=", color = CYAN) {
    cat(sprintf("%s%s%s\n", color, paste(rep(char, 100), collapse = ""), NC))
}

show_usage <- function() {
    log_sep("-", YELLOW)
    cat(sprintf("%sUsage:%s\n", YELLOW, NC))
    cat("  Rscript filter_chromosomes.R <genome_path.fa> [chrom_pattern] [quiet]\n\n")
    cat(sprintf("%sArguments:%s\n", YELLOW, NC))
    cat(sprintf("  %sgenome_path.fa%s Path to the input FASTA file\n", CYAN, NC))
    cat(sprintf("  %schrom_pattern%s   Optional regex filter pattern for chromosome naming (pass '' or 'null' for default)\n", CYAN, NC))
    cat(sprintf("  %squiet%s          Suppress processing log messages: 'true' or 'false' (default: 'false')\n", CYAN, NC))
    log_sep("-", YELLOW)
}

# ------- CLI Arguments Parsing & Validation ------- #
args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 1 || args[1] %in% c("-h", "--help") || nchar(trimws(args[1])) == 0) {
    show_usage()
    quit(status = 1, save = "no")
}

genome_fa   <- args[1]
pattern_arg <- if (length(args) >= 2) trimws(args[2]) else ""
quiet_arg   <- if (length(args) >= 3) trimws(args[3]) else "false"

# Validate quiet mode flag (expects deterministic third position)
quiet_clean <- tolower(quiet_arg)
if (!quiet_clean %in% c("true", "false")) {
    log_error(sprintf("The quiet parameter must be 'true' or 'false' (provided: '%s')", quiet_arg))
    quit(status = 1, save = "no")
}
QUIET <<- quiet_clean

log_step("Validating FASTA file and parameters...")

if (!file.exists(genome_fa)) {
    log_error(sprintf("FASTA file not found: '%s'", genome_fa))
    quit(status = 1, save = "no")
}

# Define fallback standard chromosome regular expression
default_pattern <- "^(chr)?([0-9]{1,3}|[XYZW]|MT?)$"

# Check whether a valid regex override was passed (non-empty string and not literal "null")
has_override <- nchar(pattern_arg) > 0 && tolower(pattern_arg) != "null"

main_pattern <- if (has_override) {
    is_valid <- tryCatch({
        grepl(pattern_arg, "")
        TRUE
    }, error = function(e) FALSE, warning = function(w) FALSE)

    if (!is_valid) {
        log_error(sprintf("Invalid regex pattern provided: '%s'", pattern_arg))
        quit(status = 1, save = "no")
    }
    log_info(sprintf("Using user-defined regex pattern: '%s'", pattern_arg))
    pattern_arg
} else {
    log_info(sprintf("Using default regex pattern: '%s'", default_pattern))
    default_pattern
}

# ------- Genome Sequence Processing & Filtering ------- #
log_step("Loading Biostrings library and reading FASTA sequence...")

suppressPackageStartupMessages(library(Biostrings))
genome <- readDNAStringSet(genome_fa, format = "fasta")

seq_names_full <- names(genome)
seq_ids <- sub("\\s.*$", "", seq_names_full)
seq_lens <- width(genome)

# Perform pattern matching on sequence identifiers
is_main_by_name <- grepl(main_pattern, seq_ids, ignore.case = TRUE)

if (sum(is_main_by_name) > 0) {
    keep <- is_main_by_name
    method <- sprintf("naming pattern ('%s')", main_pattern)
} else {
    # Fallback filtering strategy based on sequence length distribution
    ord <- order(seq_lens, decreasing = TRUE)
    sorted_lens <- seq_lens[ord]

    if (length(sorted_lens) > 1) {
        ratios <- sorted_lens[-length(sorted_lens)] / sorted_lens[-1]
        cut_idx <- which.max(ratios)
    } else {
        cut_idx <- length(sorted_lens)
    }

    keep_idx <- ord[seq_len(cut_idx)]
    keep <- seq_along(seq_ids) %in% keep_idx
    method <- "length distribution (no sequence matched the naming pattern)"
}

log_info(sprintf("Chromosome selection method: %s", method))
log_info(sprintf("Total sequences: %d | kept: %d | discarded: %d",
                 length(seq_ids), sum(keep), sum(!keep)))

if (sum(!keep) > 0 && QUIET != "true") {
    log_info("Discarded sequences:")
    for (i in seq_along(seq_ids[!keep])) {
        log_info(sprintf("  - %s (%d bp)", seq_ids[!keep][i], seq_lens[!keep][i]))
    }
}

if (sum(keep) == 0) {
    log_error("Chromosome selection discarded all sequences. Terminating execution.")
    quit(status = 1, save = "no")
}

# ------- Output FASTA Generation ------- #
log_step("Writing filtered FASTA file...")
genome.clean <- genome[keep]
writeXStringSet(genome.clean, genome_fa, format = "fasta")

log_success("Chromosome filtering completed successfully.")