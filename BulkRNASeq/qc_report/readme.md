# `qc_report` Workflow

`qc_report` is a containerized quality control workflow designed to automate sequence quality analysis for high-throughput sequencing datasets (FASTQ). 

The workflow parses a sample metadata mapping file (`samplemetadata`), reads raw sequence files from the input directory (`/data_fastq`), and executes [FastQC](https://www.bioinformatics.babraham.ac.uk/projects/fastqc/) on each individual FASTQ file (matching sample identifiers specified via the `SampleName` column, and optionally navigating structured subdirectories via `SampleFolder`). Quality control outputs for each sample (`<SampleFolder_>SampleName_fastqc.html` and `.zip`) are written directly to the designated output folder (`/results`). Only the files specified in the metadata file will be processed; any additional files present in `/data_fastq` will be ignored.

Upon completion of all sample-level FastQC runs, the workflow automatically invokes [MultiQC](https://multiqc.info/) to aggregate and compile all individual quality control metrics into a single, interactive execution report placed inside the `/results` directory.

---

## Container Execution & Usage

The tool is packaged and distributed via GitHub Container Registry (GHCR) under the Docker image:
`ghcr.io/reproduciblebioinformatics/docker4seq-qc_report-v2:latest`

### Command Syntax

```bash
docker run --rm \
  -v /path/to/workdir:/workDir \
  -v /path/to/fastq_dir:/data_fastq \
  -v /path/to/results_dir:/results \
  ghcr.io/reproduciblebioinformatics/docker4seq-qc_report-v2:latest \
  bash /home/start.sh <inputDir> <outDir> <metadata> <metadata_sep> <threads> <quiet>
```

---

## Directory Mounts (Volume Mapping)

| Mount Point | Flag | Description |
| :--- | :--- | :--- |
| `/workDir` | `io` | Working folder for execution and temporary file storage. |
| `/data_fastq` | `in` | Input folder where raw FASTQ files are located. |
| `/results` | `out` | Destination directory where FastQC outputs and the aggregate MultiQC report are written. |

---

## Inputs & Configuration Parameters

### File Inputs

* **`metadata`** (`flag: cp`): Path to the sample metadata file (CSV or TSV format). It maps samples to FASTQ files via the `SampleName` column (and optional `SampleFolder` column).

### Command-line Parameters

| Parameter | Description |
| :--- | :--- |
| **`inputDir`** | Specifies the container-relative or absolute path to input FASTQ files (`/data_fastq`). |
| **`outDir`** | Specifies the container-relative or absolute path where execution results will be written (`/results`). |
| **`metadata`** | Path to the metadata mapping file passed to the script. |
| **`metadata_sep`** | File separator (typically `,` or `;` for CSV, `\t` or `tab` for TSV). |
| **`threads`** | Integer indicating the number of CPU cores to be used by the application. |
| **`quiet`** | Set to `true` to suppress tool processing messages; set to `false` to keep verbose logging enabled. |

---

## Implementation Details

The workflow execution logic was generated using the **Baryon** configuration parser and builder. Specifically, the generated Python script (`qc_report.py`)—derived from the `.bala` specification—was utilized to execute, benchmark, and validate the quality control pipeline across test datasets. The `raw_data` directory contains the datasets used for testing.

**Test command line:**

```bash
python qc_report.py "./workdir" "./raw_data" "./results" "./raw_data/sampleMetaData.csv" "," 10 false
```

---

## Auxiliary Scripts

### `start.sh`

The entrypoint script invoked by the container (`bash /home/start.sh ...`). It orchestrates the full pipeline: argument validation, metadata validation, per-sample FastQC execution, and the final MultiQC aggregation.

**Usage**

```bash
bash start.sh <inputDir> <outDir> <metadata> <metadata_sep> <threads> <quiet>
```

**Arguments**

| Argument | Required | Description |
| :--- | :--- | :--- |
| `inputDir` | Yes | Base directory containing raw or structured FASTQ files. |
| `outDir` | Yes | Output directory for FastQC and MultiQC results. Must exist and be empty. |
| `metadata` | Yes | Path to the metadata file containing sample names and folders. |
| `metadata_sep` | Yes | Field separator used in the metadata file (e.g. `;` or `,`). |
| `threads` | Yes | Number of parallel threads (positive integer; capped automatically to the available CPU cores). |
| `quiet` | Yes | Set to `true` to suppress `INFO`/`PROCESS` log messages (also silences MultiQC's own logging via `--quiet`); set to `false` for verbose logging. Warnings, errors, and success messages are always shown regardless of this setting. |

**Execution flow**

1. Validates argument count and the `quiet` value (`true`/`false`).
2. Validates `threads` (must be a positive integer; requests exceeding available CPU cores are capped with a warning).
3. Checks that `inputDir` exists, `outDir` exists and is empty, and `metadata` exists.
4. Delegates content-level metadata validation to `check_samplemetadata.R`, aborting the pipeline on failure.
5. Parses the metadata header to locate the `SampleName` and optional `SampleFolder` columns.
6. Iterates over each metadata row, running FastQC on the corresponding FASTQ file (skipping rows referencing missing files, with a warning). Output files are renamed with a `SampleFolder_` prefix when applicable and moved into `outDir`.
7. Runs MultiQC against `outDir` once at least one FastQC output has been produced; aborts if none were generated.

**Exit behavior**

Exits with status `1` on any parameter, path, metadata, or MultiQC failure. Exits with status `0` and a success message once MultiQC has completed.

### `check_samplemetadata.R`

An R validation script invoked internally by `start.sh` before any FastQC execution begins. It verifies the structural integrity and content of the sample metadata file, preventing the pipeline from running against malformed input.

**Usage**

```bash
Rscript check_samplemetadata.R <METADATA_FILE> <SEPARATOR> [SEQ_TYPE]
```

**Arguments**

| Argument | Required | Description |
| :--- | :--- | :--- |
| `METADATA_FILE` | Yes | Path to the metadata CSV/TSV file to validate. |
| `SEPARATOR` | Yes | Field separator used in the file (e.g. `;` or `,`). |
| `SEQ_TYPE` | No | Sequencing mode check: `se` (Single-End) or `pe` (Paired-End). Not passed by `start.sh`. |

**Validation checks performed**

1. Confirms the metadata file exists and is not empty.
2. Confirms the specified `SEPARATOR` is actually present in the header line.
3. Rejects the file if it contains blank lines.
4. Confirms the presence of all expected columns: `SampleName`, `SampleFolder`, `sampleNumber`, `Batch`, `Covariate`, `VisName`.
5. Rejects missing/empty values in the required columns `SampleName`, `sampleNumber`, `Covariate`, `VisName`.
6. Validates the `Batch` column, allowing either a populated value or an explicit `NA`/`N/A` placeholder (case-insensitive); truly empty cells are rejected.
7. If `SEQ_TYPE` is provided, validates the frequency of `sampleNumber` values: exactly one occurrence per sample for `se` mode, exactly two occurrences per sample for `pe` mode.

**Exit behavior**

The script exits with status `0` and logs a success message if all checks pass. On any validation failure, it prints an error to `stderr` and exits with status `1`, causing `start.sh` to terminate the pipeline before any FastQC/MultiQC processing occurs.
