#!/usr/bin/env Rscript

# ------- Logger and Formatting Setup ------- #
SCRIPT_NAME <- "remove_mitochondrion.R"

# Colori ANSI
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
    cat("  Rscript remove_mitochondrion.R <genome_path.fa> [quiet]\n\n")
    cat(sprintf("%sArguments:%s\n", YELLOW, NC))
    cat(sprintf("  %sgenome_path.fa%s Path to the input FASTA file\n", CYAN, NC))
    cat(sprintf("  %squiet%s          Suppress processing log messages: 'true' or 'false' (default: 'false')\n", CYAN, NC))
    log_sep("-", YELLOW)
}

# ------- Parameter Parsing & Checks ------- #
args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 1 || args[1] %in% c("-h", "--help") || nchar(trimws(args[1])) == 0) {
    show_usage()
    quit(status = 1, save = "no")
}

genome_fa <- args[1]
quiet_arg <- if (length(args) >= 2) args[2] else "false"

# Validazione parametro quiet
quiet_clean <- tolower(trimws(quiet_arg))
if (!quiet_clean %in% c("true", "false")) {
    log_error(sprintf("The quiet parameter must be 'true' or 'false' (provided: '%s')", quiet_arg))
    quit(status = 1, save = "no")
}
QUIET <<- quiet_clean

log_step("Validating FASTA file...")

if (!file.exists(genome_fa)) {
    log_error(sprintf("FASTA file not found: '%s'", genome_fa))
    quit(status = 2, save = "no")
}

# ------- Processing Genome Sequences ------- #
log_step("Loading Biostrings library and reading FASTA sequence...")

suppressPackageStartupMessages(library(Biostrings))
genome <- readDNAStringSet(genome_fa, format = "fasta")

log_info("Searching for mitochondrial sequences...")
idx_to_remove <- grep("^MT|^mitochondrion|^M$", names(genome), ignore.case = TRUE)

if (length(idx_to_remove) > 0) {
    log_info(sprintf("Found %d mitochondrial sequence(s) to remove.", length(idx_to_remove)))
    genome.no_mt <- genome[-idx_to_remove]
    
    log_step("Writing updated FASTA file without mitochondrial sequences...")
    writeXStringSet(genome.no_mt, genome_fa, format = "fasta")
    
    log_success("Mitochondrial sequences removed successfully.")
    quit(status = 0, save = "no")
} else {
    log_warn("No mitochondrial sequences found in the provided FASTA file.")
    quit(status = 3, save = "no")
}