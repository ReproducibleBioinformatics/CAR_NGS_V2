# `filter` Workflow

`filter` is a containerized workflow designed to automate the statistical filtering of DESeq2 differential expression (DE) results and the corresponding count matrices for RNA-Seq quantification pipelines.

The workflow takes the full DESeq2 differential expression table (`de_full`) together with the raw and normalized counts matrices (`raw_counts`, `norm_counts`), applies user-defined `log2fc` and `padj` (FDR) thresholds to identify statistically significant genes, and subsets the raw and normalized counts matrices to those genes. The resulting filtered DE table and count matrices are written directly to the designated output folder (`results`), ready to be used as input for downstream visualization, enrichment, or reporting steps.

---

## Container Execution & Usage

The tool is packaged and distributed via GitHub Container Registry (GHCR) under the Docker image:
`ghcr.io/reproduciblebioinformatics/docker4seq-filter-v2:latest`

Execution is driven by a wrapper script generated from the `filter.bala` specification via [**Baryon**](https://github.com/Fairflow-BioinformaticsFramework/Baryonlang), Fairflow's `.bala`-to-source-code generator. Baryon translates the `.bala` specification into an equivalent runnable script in the target language (Python, R, etc.), which validates the inputs, prepares an isolated scratch working directory, copies every file declared with `flag=cp` in the `.bala` spec (`de_full`, `raw_counts`, `norm_counts`) into it, assembles the corresponding `docker run` command from the `.bala` `usage` template, and finally executes it. See the [Baryon repository](https://github.com/Fairflow-BioinformaticsFramework/Baryonlang) for details on installing Baryon and generating the wrapper script for your language of choice.

### Command Syntax

```bash
python filter.py <workdir> <outdir> <de_full> <raw_counts> <norm_counts> <log2fc> <padj> <threads> <quiet>
```

### Manual Docker Execution

Users who prefer to skip the Baryon-generated wrapper can invoke the container directly with `docker run`. In that case, the `flag=cp` inputs (`de_full`, `raw_counts`, `norm_counts`) must be copied (or bind-mounted) into the `/workDir` mount beforehand, since `start.sh` expects plain filesystem paths, not host paths outside the container:

```bash
docker run --rm \
  -v /path/to/workdir:/workDir \
  -v /path/to/results_dir:/results \
  ghcr.io/reproduciblebioinformatics/docker4seq-filter-v2:latest \
  bash /home/start.sh /workDir/<de_full> /workDir/<raw_counts> /workDir/<norm_counts> /results <log2fc> <padj> <threads> <quiet>
```

where `<de_full>`, `<raw_counts>`, and `<norm_counts>` are the names of the files previously copied into `/path/to/workdir` on the host (so that they appear under `/workDir` inside the container). See the [`start.sh`](#startsh) section below for the full argument reference.

---

## Directory Mounts (Volume Mapping)

| Mount Point | Flag | Description |
| :--- | :--- | :--- |
| `/workDir` | `io` | Working folder for execution and temporary file storage. In the Baryon-generated workflow this is mapped to an auto-numbered `<workdir>/scratchN` folder, into which every `flag=cp` file (`de_full`, `raw_counts`, `norm_counts`) is copied before the container starts; when running manually, the same files must be copied here by hand. |
| `/results` | `out` | Scratch/destination directory where the container is mounted and the filtered DE table and count matrices are written. In the Baryon-generated workflow this is mapped to an auto-numbered `<outdir>/outputN` folder. |

---

## Inputs & Configuration Parameters

### File Inputs

* **`de_full`** (`flag: cp`): Contains the full DESeq2 differential expression results table, including the `log2FoldChange` and `padj` statistical columns used for filtering.
* **`raw_counts`** (`flag: cp`): Contains the raw (non-normalized) gene counts matrix, subset to the significant genes identified in `de_full`.
* **`norm_counts`** (`flag: cp`): Contains the normalized gene counts matrix, subset to the significant genes identified in `de_full`.

### Command-line Parameters

| Parameter | Description |
| :--- | :--- |
| **`results`** | Output directory for the filtered DE table and count matrices. Must exist and be empty. |
| **`de_full`** | Path to the full differential expression analysis file. |
| **`raw_counts`** | Path to the raw counts matrix file. |
| **`norm_counts`** | Path to the normalized counts matrix file. |
| **`log2fc`** | Log2 fold-change threshold. Must be numeric and non-negative, since it represents an absolute fold-change cutoff applied as `abs(log2FoldChange) >= log2fc` (e.g., `1`). |
| **`padj`** | Adjusted p-value / FDR threshold. Must be numeric, strictly greater than `0` and up to `1` inclusive (e.g., `0.1`). |
| **`threads`** | Integer indicating the number of parallel threads used for `data.table` I/O (Mandatory, positive integer). Requests exceeding available CPU cores are automatically capped. |
| **`quiet`** | Set to `true` to suppress tool `INFO`/`PROCESS` log messages; set to `false` to keep verbose logging enabled (Mandatory: `true` or `false`, no default). Warnings, errors, and success messages are always shown regardless of this setting. |

---

## Implementation Details

The workflow execution logic was generated using [**Baryon**](https://github.com/Fairflow-BioinformaticsFramework/Baryonlang), Fairflow's configuration parser and code builder. Specifically, the generated Python script (`filter.py`)—derived from the `filter.bala` specification—was used to execute, benchmark, and validate the filtering pipeline. Baryon can regenerate the equivalent wrapper in other supported target languages directly from the same `.bala` file; refer to the Baryon repository for the list of supported languages and generation instructions. The workflow wraps an R/`data.table` filtering routine (`filter_de_results.R`), installed inside the container image, and applies the `log2fc`/`padj` significance thresholds to a DESeq2-style full results table to derive a filtered DE table and matching raw/normalized count matrices.

**Test command line:**

```bash
python filter.py "./workdir" "./results" "./raw_data/DE_full.txt" "./raw_data/raw_counts.txt" "./raw_data/norm_counts.txt" 1 0.05 10 false
```

---

## Auxiliary Scripts

### `start.sh`

The entrypoint script invoked inside the container (`bash /home/start.sh ...`), launched either by the Baryon-generated wrapper or manually via `docker run`. It orchestrates the full in-container pipeline: argument validation, results/input checks, and execution of the DE results filtering script.

**Usage**

```bash
bash start.sh <de_full> <raw_counts> <norm_counts> <results> <log2fc> <padj> <threads> <quiet>
```

**Arguments (all mandatory)**

| Argument | Required | Description |
| :--- | :--- | :--- |
| `de_full` | Yes | Path to the full differential expression analysis file. |
| `raw_counts` | Yes | Path to the raw counts matrix file. |
| `norm_counts` | Yes | Path to the normalized counts matrix file. |
| `results` | Yes | Output directory for filtered results. Must exist and be empty. |
| `log2fc` | Yes | Log2 fold change threshold, non-negative (e.g., `1`). |
| `padj` | Yes | Adjusted p-value / FDR threshold (`0` exclusive - `1` inclusive, e.g., `0.1`). |
| `threads` | Yes | Number of parallel threads (positive integer; requests exceeding available CPU cores are capped automatically). No default. |
| `quiet` | Yes | Set to `true` to suppress `INFO`/`PROCESS` log messages; set to `false` for verbose logging. No default. |

**Execution flow**

1. Validates argument count (exactly 8 required) and the `quiet` value (`true`/`false`), before any other output is printed.
2. Validates `threads` (must be a positive integer; requests exceeding available CPU cores are capped with a warning) and exports `OMP_NUM_THREADS`.
3. Checks that `results` exists and is empty, and that `de_full`, `raw_counts`, and `norm_counts` all exist.
4. Validates `log2fc` (numeric, non-negative) and `padj` (numeric, `0` exclusive - `1` inclusive).
5. Runs `filter_de_results.R` on the validated inputs, forwarding `de_full`, `raw_counts`, `norm_counts`, `results`, `log2fc`, `padj`, `threads`, and `quiet`.
6. Reports success or failure based on the exit status of `filter_de_results.R`.

**Exit behavior**

Exits with status `1` on invalid argument count, or on an invalid `quiet`, `threads`, `results`, missing input file, `log2fc`, or `padj` value. Exits with status `2` if `filter_de_results.R` fails (non-zero exit status). Exits with status `0` and a success message once the filtered DE table and count matrices have been generated.

### `filter_de_results.R`

An R script invoked internally by `start.sh` to apply the `log2fc`/`padj` significance thresholds to the DESeq2 full results table and derive the corresponding filtered outputs.

**Usage**

```bash
Rscript filter_de_results.R <de_full> <raw_counts> <norm_counts> <results> <log2fc> <padj> <threads> <quiet>
```

**Arguments (all mandatory)**

| Argument | Required | Description |
| :--- | :--- | :--- |
| `de_full` | Yes | Path to the full differential expression analysis file. |
| `raw_counts` | Yes | Path to the raw counts matrix file. |
| `norm_counts` | Yes | Path to the normalized counts matrix file. |
| `results` | Yes | Output directory for filtered results. Must exist and be empty. |
| `log2fc` | Yes | Log2 fold change threshold, non-negative. |
| `padj` | Yes | Adjusted p-value / FDR threshold (`0` exclusive - `1` inclusive). |
| `threads` | Yes | Number of parallel threads for `data.table` I/O (positive integer). No default. |
| `quiet` | Yes | Suppress processing log messages: `true` or `false`. No default. |

**Behavior**

1. Validates argument count (exactly 8) and the `quiet` value (`true`/`false`), before any other output is printed.
2. Validates `threads` (positive integer) and configures `data.table` parallel I/O via `setDTthreads`.
3. Checks that `results` exists and is empty, and that `de_full`, `raw_counts`, and `norm_counts` all exist.
4. Validates `log2fc` (numeric, non-negative) and `padj` (numeric, `0` exclusive - `1` inclusive).
5. Loads `de_full`, `raw_counts`, and `norm_counts` as `data.table` objects via `fread`, using `threads` for parallel I/O.
6. Verifies that `de_full` contains the required `padj` and `log2FoldChange` columns.
7. Removes rows with `NA` values in `padj` or `log2FoldChange`, then selects genes satisfying `padj <= padj_threshold & abs(log2FoldChange) >= log2fc_threshold`.
8. Subsets `raw_counts` and `norm_counts` to the significant genes (matched on the first/primary ID column of each file), warning if no gene IDs match across files.
9. Writes `DE_FULL.txt`, `DE_Filtered.txt`, `DE_counts.txt`, and `DE_normalizedCounts.txt` into `results`, and sets permissive (`0777`) file permissions on the generated outputs.

**Exit behavior**

Exits with status `1` on invalid arguments, `quiet`, `threads`, `results`, missing input file, `log2fc`, or `padj` values. Exits with status `2` if `de_full` is missing the required `padj`/`log2FoldChange` columns. Exits with status `3` if writing the output files fails. Exits with status `0` once the filtered outputs have been generated successfully.

---

## Docker Image

The image is based on `ubuntu:24.04` and bundles:

* **R** (`r-base`) and **`r-cran-data.table`** for the filtering script.

`filter.R` is copied into `/usr/local/bin/filter.R` and made executable, and `start.sh` is copied into `/home/start.sh` and made executable. The container's default working directory is `/home`, with `bash` as the default `CMD`.