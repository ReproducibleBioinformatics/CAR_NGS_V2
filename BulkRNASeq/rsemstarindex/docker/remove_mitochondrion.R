#!/usr/bin/env Rscript
SCRIPT_NAME <- "remove_mitochondrion.R"
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
    cat("  Rscript remove_mitochondrion.R <genome_path.fa> <quiet>\n\n")
    cat(sprintf("%sArguments (all mandatory):%s\n", YELLOW, NC))
    cat(sprintf("  %sgenome_path.fa%s Path to the input FASTA file\n", CYAN, NC))
    cat(sprintf("  %squiet%s          Suppress non-error log messages: 'true' or 'false'\n", CYAN, NC))
    log_sep("-", YELLOW)
}
# ------- CLI Arguments Parsing & Validation ------- #
args <- commandArgs(trailingOnly = TRUE)
# ------- Both positional parameters are mandatory ------- #
if (length(args) < 2 || args[1] %in% c("-h", "--help")) { show_usage(); quit(status = 1, save = "no");}
genome_fa <- trimws(args[1])
quiet_arg <- trimws(args[2])
if (nchar(genome_fa) == 0) {log_error("The genome_path.fa parameter is mandatory and cannot be empty."); show_usage(); quit(status = 1, save = "no");}
quiet_clean <- tolower(quiet_arg)
if (!quiet_clean %in% c("true", "false")) {log_error(sprintf("The QUIET parameter must be 'true' or 'false' (provided: '%s'). Defaulting to 'false' and continuing.", quiet_arg));
} else if (quiet_clean == "true") { QUIET <- TRUE;}
if (!file.exists(genome_fa)) {log_error(sprintf("FASTA file not found: '%s'", genome_fa)); quit(status = 2, save = "no");}
# ------- Processing Genome Sequences ------- #
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