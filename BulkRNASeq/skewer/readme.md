# `skewer` Workflow

`skewer` is a containerized adapter-trimming workflow designed to automate sequencing adapter removal for high-throughput sequencing datasets (FASTQ), for both Single-End (SE) and Paired-End (PE) data.

The workflow parses a sample metadata mapping file (`samplemetadata`), reads raw sequence files from the input directory (`/data_fastq`), and executes [Skewer](https://github.com/relipmoc/skewer) on each sample (matching sample identifiers specified via the `SampleName` column, and optionally navigating structured subdirectories via `SampleFolder`), removing the specified 5' and 3' adapter sequences. In Paired-End mode, samples are matched into read pairs based on the `SampleNumber` column of the metadata file. Trimmed, gzip-compressed FASTQ outputs (`<SampleFolder_>SampleName`, or `<SampleFolder_>SampleName` for each mate in PE mode) are written directly to the designated output folder (`/results`). Only the files specified in the metadata file will be processed; any additional files present in `/data_fastq` will be ignored.

Upon completion of all sample-level trimming runs, the workflow writes an updated copy of the metadata file (reflecting the renamed/trimmed sample file names, with the `SampleFolder` column cleared where applicable) inside the `/results` directory.

---

## Container Execution & Usage

The tool is packaged and distributed via GitHub Container Registry (GHCR) under the Docker image:
`ghcr.io/reproduciblebioinformatics/docker4seq-skewer-v2:latest`

## Inputs & Configuration Parameters

### File Inputs

* **`metadata`**: Path to the sample metadata file (CSV or TSV format). It maps samples to FASTQ files via the `SampleName` column (and optional `SampleFolder` column), and pairs Paired-End reads via the `SampleNumber` column.

### Command-line Parameters

| Parameter | Description |
| :--- | :--- |
| **`inputDir`** | Specifies the container-relative or absolute path to input FASTQ files (`/data_fastq`). |
| **`outDir`** | Specifies the container-relative or absolute path where execution results will be written (`/results`). |
| **`adapter5`** | Character string indicating the 5' adapter sequence (DNA bases only, IUPAC ambiguity codes allowed). Default: `AGATCGGAAGAGCACACGTCTGAACTCCAGTCA`. |
| **`adapter3`** | Character string indicating the 3' adapter sequence. Required for Paired-End (`pe`) mode; for Single-End (`se`) mode, pass `none`, `null`, or `""`. Default: `AGATCGGAAGAGCGTCGTGTAGGGAAAGAGTGT`. |
| **`seq_type`** | Sequencing mode: `se` (Single-End) or `pe` (Paired-End). |
| **`metadata`** | Path to the metadata mapping file passed to the script. |
| **`separator`** | File separator (`,` or `;` for CSV, `\t` or `tab` for TSV). |
| **`threads`** | Integer indicating the number of CPU cores to be used by the application. |
| **`quiet`** | Set to `true` to suppress tool processing messages; set to `false` to keep verbose logging enabled. |

---

## Implementation Details

The workflow execution logic was generated using the **Baryon** configuration parser and builder. Specifically, the generated Python script (`skewer.py`)—derived from the `skewer.bala` specification—was utilized to execute, benchmark, and validate the adapter-trimming pipeline across test datasets. The `raw_data` directory contains the datasets used for testing.

**Test command line:**

```bash
python skewer.py "./workdir" "./raw_data" "./results" "AGATCGGAAGAGCACACGTCTGAACTCCAGTCA" "AGATCGGAAGAGCGTCGTGTAGGGAAAGAGTGT" "pe" "./raw_data/sampleMetaData.csv" "," 10 false
```

---
### Manual Docker Launch Example

When running the container manually (i.e., not via a Baryon-generated script), the sample metadata file is **not** automatically placed inside the working directory. You must therefore mount, as `/workDir`, the local folder that actually contains your metadata file, so that the script can locate it at `/workDir/<metadata>`.

```bash
docker run --rm \
  -v /path/to/workdir:/workDir \
  -v /path/to/fastq_dir:/data_fastq \
  -v /path/to/results_dir:/results \
  ghcr.io/reproduciblebioinformatics/docker4seq-skewer-v2:latest \
  bash /home/start.sh /data_fastq /results <adapter5> <adapter3> <seq_type> /workDir/<metadata> <separator> <threads> <quiet>
```

---

## Auxiliary Scripts

### `start.sh`

The entrypoint script invoked by the container (`bash /home/start.sh ...`). It orchestrates the full pipeline: argument validation, metadata validation, per-sample (or per-pair) Skewer execution, and generation of the updated metadata file.

**Execution flow**

1. Validates argument count and the `quiet` value (`true`/`false`).
2. Validates `threads` (must be a positive integer; requests exceeding available CPU cores are capped with a warning).
3. Validates and normalizes the `separator` value (accepts `,`, `;`, `\t`, or `tab`).
4. Checks that `inputDir` exists, `outDir` exists and is empty, and `metadata` exists.
5. Validates `adapter5` (mandatory, DNA/IUPAC characters only), `adapter3` (mandatory for `pe`; DNA/IUPAC characters only unless `none`/`null`/empty for `se`), and `seq_type` (`se` or `pe`).
6. Delegates content-level metadata validation to `check_samplemetadata.R` (including the `SampleNumber` frequency check consistent with `seq_type`), aborting the pipeline on failure.
7. Parses the metadata header to locate the `SampleName`, `SampleNumber`, and optional `SampleFolder` columns, then loads all rows into memory and sorts them by `SampleNumber`.
8. Iterates over the sorted samples:
   * **SE mode**: runs Skewer on each individual FASTQ file, skipping (with a warning) rows referencing missing files.
   * **PE mode**: matches consecutive metadata rows sharing the same `SampleNumber` into read pairs and runs Skewer in paired mode, skipping (with a warning) unmatched or incomplete pairs.
9. Trimmed output files are renamed with a `SampleFolder_` prefix when applicable and moved into `outDir`; the metadata `SampleName` (and `SampleFolder`, if present) fields are updated to reflect the new file names.
10. Writes the updated metadata file (containing only the successfully processed samples) into `outDir`, using the same file extension convention as the separator (`.tsv` for tab, `.csv` otherwise), named `<original_basename>_skewer.<ext>`.
11. Removes temporary working files and aborts if no trimmed FASTQ outputs were produced.

**Exit behavior**

Exits with status `1` on any parameter, path, metadata, or Skewer failure (with no trimmed outputs produced). Exits with status `0` and a success message once at least one trimmed FASTQ file has been generated.

### `check_samplemetadata.R`

An R validation script invoked internally by `start.sh` before any Skewer execution begins. It verifies the structural integrity and content of the sample metadata file, preventing the pipeline from running against malformed input.

**Validation checks performed**

1. Confirms the metadata file exists and is not empty.
2. Confirms the specified `SEPARATOR` is actually present in the header line.
3. Rejects the file if it contains blank lines.
4. Confirms the presence of all expected columns: `SampleName`, `SampleFolder`, `SampleNumber`, `Batch`, `Covariate`, `VisName`.
5. Rejects missing/empty values in the required columns `SampleName`, `SampleNumber`, `Covariate`, `VisName`.
6. Validates the `Batch` column, allowing either a populated value or an explicit `NA`/`N/A` placeholder (case-insensitive); truly empty cells are rejected.
7. If `SEQ_TYPE` is `se` or `pe`, validates the frequency of `SampleNumber` values: exactly one occurrence per sample for `se` mode, exactly two occurrences per sample for `pe` mode.

**Exit behavior**

The script exits with status `0` and logs a success message if all checks pass. On any validation failure, it prints an error to `stderr` and exits with status `1`, causing `start.sh` to terminate the pipeline before any Skewer processing occurs.