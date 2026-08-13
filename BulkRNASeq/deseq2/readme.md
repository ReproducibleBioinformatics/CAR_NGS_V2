# `deseq2` Workflow

`deseq2` is a containerized workflow designed to automate differential gene expression analysis between two experimental groups using [DESeq2](https://bioconductor.org/packages/release/bioc/html/DESeq2.html).

The workflow takes a raw count expression matrix (samples in columns, genes/features in rows) and a sample metadata table, aligns samples between the two inputs, builds the DESeq2 design formula (automatically including a batch term when a `Batch` metadata column with more than one level is detected), runs the standard DESeq2 differential expression model, and filters the results by a user-defined absolute Log2 Fold Change and FDR (adjusted p-value) threshold. Both the full and filtered results, together with the corresponding filtered raw and normalized count subsets, are written directly to the designated output folder (`outDir`), ready to be used for downstream reporting or visualization.

---

## Container Execution & Usage

The tool is packaged and distributed via GitHub Container Registry (GHCR) under the Docker image:
`ghcr.io/reproduciblebioinformatics/docker4seq-deseq2-v2:latest`

Execution is driven by a wrapper script generated from the `deseq2.bala` specification via [**Baryon**](https://github.com/Fairflow-BioinformaticsFramework/Baryonlang), Fairflow's `.bala`-to-source-code generator. Baryon translates the `.bala` specification into an equivalent runnable script in the target language (Python, R, etc.), which validates the inputs, prepares an isolated scratch working directory, copies every file declared with `flag=cp` in the `.bala` spec (`matrix_path`, `metadata`) into it, assembles the corresponding `docker run` command from the `.bala` `usage` template, and finally executes it. See the [Baryon repository](https://github.com/Fairflow-BioinformaticsFramework/Baryonlang) for details on installing Baryon and generating the wrapper script for your language of choice.

### Command Syntax

```bash
python deseq2.py <workdir> <outdir> <matrix_path> <matrix_sep> <metadata> <metadata_sep> <log2fc> <fdr> <ref_covar> <target_covar> <threads> <quiet>
```

### Manual Docker Execution

Users who prefer to skip the Baryon-generated wrapper can invoke the container directly with `docker run`. In that case, the `flag=cp` inputs (`matrix_path`, `metadata`) must be copied (or bind-mounted) into the `/workDir` mount beforehand, since `start.sh` expects plain filesystem paths, not host paths outside the container:

```bash
docker run --rm \
  -v /path/to/workdir:/workDir \
  -v /path/to/results_dir:/results \
  ghcr.io/reproduciblebioinformatics/docker4seq-deseq2-v2:latest \
  bash /home/start.sh /results /workDir/<matrix_path> <matrix_sep> /workDir/<metadata> <metadata_sep> <log2fc> <fdr> <ref_covar> <target_covar> <threads> <quiet>
```

where `<matrix_path>` and `<metadata>` are the names of the count matrix/metadata files previously copied into `/path/to/workdir` on the host (so that they appear under `/workDir` inside the container). See the [`start.sh`](#startsh) section below for the full argument reference.

---

## Directory Mounts (Volume Mapping)

| Mount Point | Flag | Description |
| :--- | :--- | :--- |
| `/workDir` | `io` | Working folder for execution and temporary file storage. In the Baryon-generated workflow this is mapped to an auto-numbered `<workdir>/scratchN` folder, into which every `flag=cp` file (`matrix_path`, `metadata`) is copied before the container starts; when running manually, the same files must be copied here by hand. |
| `/results` | `out` | Scratch/destination directory where the container is mounted and the differential expression results are written. In the Baryon-generated workflow this is mapped to an auto-numbered `<outdir>/outputN` folder. |

---

## Inputs & Configuration Parameters

### File Inputs

* **`matrix_path`** (`flag: cp`): Raw count expression matrix (samples in columns, genes/features in rows), used by DESeq2 as the input count data. Accepts `.csv`, `.tsv`, or `.txt`.
* **`metadata`** (`flag: cp`): Sample metadata table containing, at minimum, a `SampleName` column matching the count matrix column names and a condition/covariate column (`Covariate`, `Condition`, `Group`, or `Treatment`, case-insensitive) holding the `ref_covar`/`target_covar` levels. An optional `Batch` column, if present with more than one level, is automatically included in the design formula.

### Command-line Parameters

| Parameter | Description |
| :--- | :--- |
| **`outDir`** | Output directory for differential expression results. Must exist and be empty. |
| **`matrix_path`** | Path to the input count matrix file (`.csv`, `.tsv`, `.txt`). |
| **`matrix_sep`** | Field separator used in the count matrix. Allowed values: `,`, `;`, `\t`, `tab`. |
| **`metadata`** | Path to the sample metadata table. |
| **`metadata_sep`** | Field separator used in the metadata file. Allowed values: `,`, `;`, `\t`, `tab`. |
| **`log2fc`** | Absolute Log2 Fold Change threshold used to filter differentially expressed genes (e.g., `1.0` for a 2-fold change). Must be a non-negative number. |
| **`fdr`** | FDR / adjusted p-value (`padj`) significance threshold used to control for multiple testing (e.g., `0.05`). Must be a number between `0` and `1`. |
| **`ref_covar`** | Reference/baseline level of the primary condition variable (e.g., `control`, `untreated`, `wildtype`), used as the denominator in the differential expression contrast. |
| **`target_covar`** | Target/experimental level of the primary condition variable (e.g., `treated`, `knockout`, `mutant`), evaluated against `ref_covar` to calculate fold change values. Must differ from `ref_covar`. |
| **`threads`** | Integer indicating the number of CPU cores to be used by the application. Requests exceeding available CPU cores are automatically capped. |
| **`quiet`** | Set to `true` to suppress tool `INFO`/`PROCESS` log messages; set to `false` to keep verbose logging enabled. Warnings, errors, and success messages are always shown regardless of this setting. |

---

## Implementation Details

The workflow execution logic was generated using [**Baryon**](https://github.com/Fairflow-BioinformaticsFramework/Baryonlang), Fairflow's configuration parser and code builder. Specifically, the generated Python script (`deseq2.py`)—derived from the `deseq2.bala` specification—was used to execute, benchmark, and validate the differential expression pipeline. Baryon can regenerate the equivalent wrapper in other supported target languages directly from the same `.bala` file; refer to the Baryon repository for the list of supported languages and generation instructions. The workflow wraps [DESeq2](https://bioconductor.org/packages/release/bioc/html/DESeq2.html), installed inside the container image via `r-bioc-deseq2`, and executes the standard DESeq2 model (`DESeqDataSetFromMatrix` → `DESeq` → `results`) on the aligned count matrix and metadata.

**Test command line:**

```bash
python deseq2.py "./workdir" "./results" "./raw_data/counts_matrix.txt" "tab" "./raw_data/metadata.csv" "," 1.0 0.05 control treated 10 false
```

---

## Auxiliary Scripts

### `start.sh`

The entrypoint script invoked inside the container (`bash /home/start.sh ...`), launched either by the Baryon-generated wrapper or manually via `docker run`. It orchestrates the full in-container pipeline: argument validation, environment/thread setup, and DESeq2 differential expression execution via `core.R`.

**Usage**

```bash
bash start.sh <results> <matrix_path> <matrix_sep> <metadata> <metadata_sep> <log2fc> <fdr> <ref_covar> <target_covar> <threads> <quiet>
```

**Arguments**

| Argument | Required | Description |
| :--- | :--- | :--- |
| `results` | Yes | Output directory for differential expression results. Must exist and be empty. |
| `matrix_path` | Yes | Path to the input count matrix file (`.csv`, `.tsv`, `.txt`). |
| `matrix_sep` | Yes | Field separator used in the count matrix (`,`, `;`, `\t`, or `tab`). |
| `metadata` | Yes | Path to the sample metadata table. |
| `metadata_sep` | Yes | Field separator used in the metadata file (`,`, `;`, `\t`, or `tab`). |
| `log2fc` | Yes | Absolute Log2 Fold Change threshold for filtering (e.g., `1.0`). |
| `fdr` | Yes | FDR / adjusted p-value significance threshold (e.g., `0.05`). |
| `ref_covar` | Yes | Baseline/control group level in metadata (e.g., `control`). |
| `target_covar` | Yes | Treatment/target group level in metadata (e.g., `treated`). |
| `threads` | Yes | Number of parallel threads (positive integer; capped automatically to the available CPU cores). |
| `quiet` | Yes | Set to `true` to suppress `INFO`/`PROCESS` log messages; set to `false` for verbose logging. |

**Execution flow**

1. Validates argument count (exactly 11 required) and the `quiet` value (`true`/`false`).
2. Validates `threads` (must be a positive integer; requests exceeding available CPU cores are capped with a warning) and exports `OMP_NUM_THREADS`.
3. Checks that `results` exists and is empty, and that both `matrix_path` and `metadata` exist.
4. Normalizes `matrix_sep` and `metadata_sep` (`,`, `;`, `\t`, `tab`, case-insensitive) via the shared `parse_separator_inplace()` function.
5. Validates `log2fc` (non-negative number) and `fdr` (number between `0` and `1`).
6. Validates that `ref_covar` and `target_covar` are different.
7. Locates `core.R` (`/usr/local/bin/core.R` or the current working directory).
8. Runs `core.R` via `Rscript`, forwarding all validated parameters, and reports success or failure.

**Exit behavior**

Exits with status `1` on invalid arguments, `quiet`, `threads`, `log2fc`, `fdr`, `ref_covar`/`target_covar`, or separator values, on a missing/non-empty `results` directory, on a missing `matrix_path`/`metadata` file, or if `core.R` cannot be located. Exits with status `2` if `core.R` fails during execution. Exits with status `0` and a success message once the differential expression results have been generated.

### `core.R`

An R script invoked internally by `start.sh` to perform the DESeq2 differential expression analysis.

**Usage**

```bash
Rscript core.R <results> <matrix_path> <matrix_sep> <metadata> <metadata_sep> <log2fc> <fdr> <ref_covar> <target_covar> <threads> <quiet>
```

**Arguments**

| Argument | Required | Description |
| :--- | :--- | :--- |
| `results` | Yes | Output directory for differential expression results (must already exist). |
| `matrix_path` | Yes | Path to the input count matrix file. |
| `matrix_sep` | Yes | Field separator used in the count matrix (`,`, `;`, `\t`, or `tab`). |
| `metadata` | Yes | Path to the sample metadata table. |
| `metadata_sep` | Yes | Field separator used in the metadata file (`,`, `;`, `\t`, or `tab`). |
| `log2fc` | Yes | Absolute Log2 Fold Change threshold for filtering. |
| `fdr` | Yes | FDR / adjusted p-value significance threshold. |
| `ref_covar` | Yes | Baseline/control group level in metadata. |
| `target_covar` | Yes | Treatment/target group level in metadata. |
| `threads` | Yes | Number of parallel threads (positive integer), used for `data.table`/I-O parallelism (`setDTthreads`). |
| `quiet` | Yes | Suppress processing log messages: `true` or `false`. |

**Behavior**

1. Validates argument count, the `quiet` value, `threads`, `log2fc`, `fdr`, separator values, existence of `results`/`matrix_path`/`metadata`, and that `ref_covar` differs from `target_covar`.
2. Loads the count matrix and metadata via `data.table::fread`, using the requested separators and thread count.
3. Aligns samples between the count matrix and metadata using a `SampleName` metadata column (or the first column as fallback if `SampleName` is not found), and detects the condition/covariate column (`Covariate`, `Condition`, `Group`, or `Treatment`, case-insensitive).
4. Filters samples to only the `ref_covar`/`target_covar` levels, relevels the condition factor with `ref_covar` as reference, and detects an optional `Batch` metadata column to include in the design formula when it has more than one level.
5. Builds the `DESeqDataSet`, runs `DESeq()`, and extracts the results table.
6. Writes `DE_FULL.txt` (full, unfiltered results), `DE_filtered.txt` (results filtered by `log2fc`/`fdr`), `<matrix_basename>_DE.txt` (raw counts subset to significant genes), and `<matrix_basename>_normalized_DE.txt` (log2-normalized counts subset to significant genes) into `results`.

**Exit behavior**

Exits with a non-zero status on any validation failure (missing/invalid arguments, missing input files, unmatched sample IDs, missing condition column, no samples matching the requested covariate levels, or reference level not found in the metadata). Completes silently with a success message once all four output files have been written.

---

## Docker Image

The image is based on `ubuntu:24.04` and bundles:

* **R** (base + `r-bioc-deseq2` + `r-cran-data.table`) for the differential expression analysis.

`core.R` is copied into `/usr/local/bin` and set as executable. `start.sh` is copied into `/home` and set as executable. The container's default working directory is `/home`, with `bash` as the default `CMD`.