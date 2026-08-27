#!/usr/bin/env Rscript
# test.R - R equivalent of test.sh
# Runs the QC Report pipeline by sourcing qc_report.R and calling the
# qc_report() function directly, instead of invoking qc_report.py via python3.

SCRIPT_NAME  <- "test-qcreport"
workdir      <- "workdir"
input_dir    <- "../testdata/raw_data/"
results      <- "results/"
metadata     <- "../testdata/raw_data/sampleMetaData.csv"
metadata_sep <- ","
threads      <- 10
quiet        <- "false"

# ANSI color codes (same palette as test.sh)
NC     <- "\033[0m"
CYAN   <- "\033[0;36m"
YELLOW <- "\033[1;33m"
ORANGE <- "\033[0;33m"
GREEN  <- "\033[0;32m"
RED    <- "\033[0;31m"
PINK   <- "\033[1;35m"

QUIET <- quiet

# log_test(): mirrors the bash log_test() function, respecting QUIET
log_test <- function(msg) {
  if (QUIET == "true") return(invisible(NULL))
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat(sprintf("%s[%s] [%s PROCESS] %s%s\n", PINK, timestamp, SCRIPT_NAME, msg, NC))
}

# mkdir -p workdir results
dir.create(workdir, recursive = TRUE, showWarnings = FALSE)
dir.create(results, recursive = TRUE, showWarnings = FALSE)

log_test("Executing QC Report pipeline via R function...")

# Load the qc_report() function definition into this session.
# Adjust the path below if qc_report.R lives elsewhere relative to test.R.
source("qc_report.R")

# Call the function directly (no subprocess/system2 involved this time)
ret <- qc_report(
  workdir      = workdir,
  inputdir     = input_dir,
  outdir       = results,
  metadata     = metadata,
  metadata_sep = metadata_sep,
  threads      = threads,
  quiet        = quiet
)

if (is.null(ret)) ret <- 0

if (ret != 0) {
  log_test(paste0(RED, "qc_report() exited with status ", ret, NC))
}

quit(status = ret)
