#!/usr/bin/env Rscript
# test.R - R equivalent of test.sh
# Runs the QC Report pipeline via the R implementation (qc_report.R)
# instead of the Python wrapper (qc_report.py).

SCRIPT_NAME <- "test-qcreport"
workdir     <- "workdir"
input_dir   <- "../testdata/raw_data/"
results     <- "results/"
metadata    <- "../testdata/raw_data/sampleMetaData.csv"
metadata_sep <- ","
threads     <- 10
quiet       <- "false"

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

# Build the argument vector for qc_report.R (positional args, same order
# expected by commandArgs(trailingOnly = TRUE) in qc_report.R)
qc_args <- c(workdir, input_dir, results, metadata, metadata_sep, as.character(threads), quiet)

# Launch qc_report.R with Rscript, forwarding stdout/stderr live
status <- system2("Rscript", args = c(shQuote("qc_report.R"), shQuote(qc_args)),
                   stdout = "", stderr = "")

if (status != 0) {
  log_test(paste0(RED, "qc_report.R exited with status ", status, NC))
}

quit(status = status)
