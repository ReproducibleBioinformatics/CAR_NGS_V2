# `pca` Workflow

`pca` is a containerized workflow designed to automate Principal Component Analysis (PCA) of RNA-Seq (or other omics) expression matrices, for exploratory quality control and sample clustering visualization.

The workflow takes a single expression/count matrix file (samples in columns, features/genes in rows) and a sample metadata file, and computes a PCA projection using one of three selectable strategies: a **standard** `prcomp`-based PCA (with optional log2 transformation and zero-variance feature removal), or a **DESeq2**-based PCA computed on variance-stabilized data, either **blind** (`deseq`) or **design-aware / size-factor normalized** (`deseqNormalized`). Samples are colored on the resulting plot according to a `Covariate` column provided in the metadata file. Both the count matrix and the metadata file may use a custom field separator (comma, semicolon, or tab). The resulting PCA plot is written directly to the designated output folder (`outDir`).

---

## Container Execution & Usage

The tool is packaged and distributed via GitHub Container Registry (GHCR) under the Docker image:
`ghcr.io/reproduciblebioinformatics/docker4seq-pca-v2:latest`

Execution is driven by a wrapper script generated from the `pca.bala` specification via [**Baryon**](https://github.com/Fairflow-BioinformaticsFramework/Baryonlang), Fairflow's `.bala`-to-source-code generator. Baryon translates the `.bala` specification into an equivalent runnable script in the target language (Python, R, etc.), which validates the inputs, prepares an isolated scratch working directory, copies every file declared with `flag=cp` in the `.bala` spec (`matrix_path`, `metadata`) into it, assembles the corresponding `docker run` command from the `.bala` `usage` template, and finally executes it. See the [Baryon repository](https://github.com/Fairflow-BioinformaticsFramework/Baryonlang) for details on installing Baryon and generating the wrapper script for your language of choice.

### Command Syntax

```bash
python pca.py <workdir> <outdir> <matrix_path> <matrix_sep> <metadata> <metadata_sep> <pca_type> <log_transform> <remove_zero_var> <threads> <quiet>
```

### Manual Docker Execution

Users who prefer to skip the Baryon-generated wrapper can invoke the container directly with `docker run`. In that case, the `flag=cp` inputs (`matrix_path`, `metadata`) must be copied (or bind-mounted) into the `/workDir` mount beforehand, since `start.sh` expects plain filesystem paths, not host paths outside the container:

```bash
docker run --rm \
  -v /path/to/workdir:/workDir \
  -v /path/to/results_dir:/results \
  ghcr.io/reproduciblebioinformatics/docker4seq-pca-v2:latest \
  bash /home/start.sh /results /workDir/<matrix_path> <matrix_sep> /workDir/<metadata> <metadata_sep> <pca_type> <log_transform> <remove_zero_var> <threads> <quiet>
```

where `<matrix_path>` and `<metadata>` are the names of the count matrix / metadata files previously copied into `/path/to/workdir` on the host (so that they appear under `/workDir` inside the container). See the [`start.sh`](#startsh) section below for the full argument reference.

---

## Directory Mounts (Volume Mapping)

| Mount Point | Flag | Description |
| :--- | :--- | :--- |
| `/workDir` | `io` | Working folder for execution and temporary file storage. In the Baryon-generated workflow this is mapped to an auto-numbered `<workdir>/scratchN` folder, into which every `flag=cp` file (`matrix_path`, `metadata`) is copied before the container starts; when running manually, the same files must be copied here by hand. |
| `/results` | `out` | Scratch/destination directory where the container is mounted and the PCA plot is written. In the Baryon-generated workflow this is mapped to an auto-numbered `<outdir>/outputN` folder. |

---

## Inputs & Configuration Parameters

### File Inputs

* **`matrix_path`** (`flag: cp`): Path to the input expression/count matrix file (samples in columns, features/genes in rows). Accepts `.csv`, `.tsv`, or `.txt`.
* **`metadata`** (`flag: cp`): A CSV or TSV file containing sample metadata. Must include a `SampleName` column (matched against the matrix column headers) and a `Covariate` column, used to color samples on the PCA plot.

### Command-line Parameters

| Parameter | Description |
| :--- | :--- |
| **`outDir`** | Output directory where PCA results will be stored. Must exist and be empty. |
| **`matrix_path`** | Path to the input expression/count matrix file. |
| **`matrix_sep`** | Field separator for the count matrix file. Allowed values: `,`, `;`, `\t`, `tab`. |
| **`metadata`** | Path to the sample metadata file. |
| **`metadata_sep`** | Field separator for the metadata file. Allowed values: `,`, `;`, `\t`, `tab`. |
| **`pca_type`** | Normalization/transformation strategy applied before PCA. Allowed values: `standard` (no advanced normalization, computed via `prcomp`), `deseq` (DESeq2 blind variance-stabilizing transformation), `deseqNormalized` (DESeq2 design-aware, size-factor/covariate-adjusted transformation). |
| **`log_transform`** | Applies a log2(x + 1) transformation to the expression matrix before PCA to reduce skewness and stabilize variance (only used when `pca_type` is `standard`). `true` or `false`. |
| **`remove_zero_var`** | Filters out zero-variance features prior to PCA to avoid numerical errors in `prcomp` (only used when `pca_type` is `standard`). `true` or `false`. |
| **`threads`** | Integer indicating the number of CPU cores to be used by the application (Optional, default: `10`). Requests exceeding available CPU cores are automatically capped. |
| **`quiet`** | Set to `true` to suppress tool `INFO`/`PROCESS` log messages; set to `false` to keep verbose logging enabled. Warnings, errors, and success messages are always shown regardless of this setting (Optional, default: `false`). |

---

## Implementation Details

The workflow execution logic was generated using [**Baryon**](https://github.com/Fairflow-BioinformaticsFramework/Baryonlang), Fairflow's configuration parser and code builder. Specifically, the generated Python script (`pca.py`)—derived from the `pca.bala` specification—was used to execute, benchmark, and validate the PCA pipeline. Baryon can regenerate the equivalent wrapper in other supported target languages directly from the same `.bala` file; refer to the Baryon repository for the list of supported languages and generation instructions. The workflow wraps base R `prcomp` PCA together with [DESeq2](https://bioconductor.org/packages/release/bioc/html/DESeq2.html)-based variance-stabilized PCA, both installed inside the container image, and executes either `plot_pca.R` or `run_deseq2.R` (depending on `pca_type`) to produce the PCA plot from the input count matrix and its corresponding sample metadata.

**Test command line:**

```bash
python pca.py "./workdir" "./results" "./raw_data/counts.csv" "," "./raw_data/metadata.csv" "," deseq true true 10 false
```

---

## Auxiliary Scripts

### `start.sh`

The entrypoint script invoked inside the container (`bash /home/start.sh ...`), launched either by the Baryon-generated wrapper or manually via `docker run`. It orchestrates the full in-container pipeline: argument validation, and dispatch to the correct R script (`plot_pca.R` or `run_deseq2.R`) depending on the selected `pca_type`.

**Usage**

```bash
bash start.sh <results> <matrix_path> <matrix_sep> <metadata> <metadata_sep> <pca_type> <log_transform> <remove_zero_var> <threads> <quiet>
```

**Arguments (all mandatory)**

| Argument | Required | Description |
| :--- | :--- | :--- |
| `results` | Yes | Output directory where PCA results will be stored. Must exist and be empty. |
| `matrix_path` | Yes | Path to single count matrix file (`.csv`, `.tsv`, `.txt`). |
| `matrix_sep` | Yes | Field separator for the count matrix file (`,`, `;`, `\t`, `tab`). |
| `metadata` | Yes | Path to metadata file. |
| `metadata_sep` | Yes | Field separator for the metadata file (`,`, `;`, `\t`, `tab`). |
| `pca_type` | Yes | Type of PCA analysis: `standard`, `deseq`, or `deseqNormalized`. |
| `log_transform` | Yes | Apply log2 transformation: `true` or `false`. |
| `remove_zero_var` | Yes | Filter zero variance genes: `true` or `false`. |
| `threads` | Yes | Number of parallel threads (positive integer; capped automatically to the available CPU cores). |
| `quiet` | Yes | Suppress processing log messages: `true` or `false`. |

**Execution flow**

1. Validates the exact argument count (10 required) and the `quiet` value (`true`/`false`), validated upfront so that logging behaves correctly from the first message.
2. Validates and normalizes `log_transform` and `remove_zero_var` (accepting `true`/`1`/`yes` and `false`/`0`/`no`, case-insensitive).
3. Prints the full pipeline execution context (results dir, matrix/metadata paths and separators, `pca_type`, transform/filter flags, threads, quiet mode).
4. Validates `threads` (must be a positive integer; requests exceeding available CPU cores are capped with a warning) and exports `OMP_NUM_THREADS`.
5. Checks that the `results` directory exists and is empty, and that both `matrix_path` and `metadata` exist and are non-empty files.
6. Validates and normalizes `metadata_sep` (`,`, `;`, `\t`, `tab`, case-insensitive).
7. Validates `pca_type` (`standard`, `deseq`, `deseqnormalized`).
8. Dispatches execution: if `pca_type` is `standard`, runs `/usr/local/bin/plot_pca.R`; otherwise (`deseq` or `deseqNormalized`), runs `/usr/local/bin/run_deseq2.R` with the corresponding mode.
9. Reports success or failure based on the exit status of the invoked R script.

**Exit behavior**

Exits with status `1` on invalid argument count, or invalid `quiet`, `log_transform`, `remove_zero_var`, `threads`, `results`/`matrix_path`/`metadata` validation, `metadata_sep`, or `pca_type` values. Exits with status `2` if the invoked R script (`plot_pca.R` or `run_deseq2.R`) fails. Exits with status `0` and a success message once the PCA plot has been generated.

### `plot_pca.R`

An R script invoked internally by `start.sh` (when `pca_type` is `standard`) to compute a standard `prcomp`-based PCA on the (optionally transformed and filtered) expression matrix.

**Usage**

```bash
Rscript plot_pca.R <input_file> <expr_sep> <metadata> <metadata_sep> <results> <log_transform> <remove_zero_var> <threads> <quiet>
```

**Arguments**

| Argument | Required | Description |
| :--- | :--- | :--- |
| `input_file` | Yes | Path to the expression matrix file. |
| `expr_sep` | Yes | Field separator for the expression matrix (`,`, `;`, `\t`, `tab`). |
| `metadata` | Yes | Path to the sample metadata file. |
| `metadata_sep` | Yes | Field separator used in metadata (`,`, `;`, `\t`, `tab`). |
| `results` | Yes | Output directory for PCA plot results (created automatically if missing). |
| `log_transform` | Yes | Apply log2(x + 1) transformation: `true` or `false`. |
| `remove_zero_var` | Yes | Remove zero variance features: `true` or `false`. |
| `threads` | Yes | Number of parallel threads (positive integer; capped automatically to the available CPU cores; also used to configure `RhpcBLASctl`, when available). |
| `quiet` | Yes | Suppress processing log messages: `true` or `false`. |

**Behavior**

1. Validates argument count (exactly 9 required) and the `quiet` value.
2. Validates `log_transform` and `remove_zero_var` (`true`/`false`).
3. Prints the pipeline execution context and validates `threads`, capping it to the available CPU cores if necessary; sets `OMP_NUM_THREADS` and, when available, the BLAS thread count via `RhpcBLASctl`.
4. Creates the `results` directory if it does not already exist.
5. Checks that `input_file` and `metadata` exist and are non-empty.
6. Validates and normalizes `expr_sep` and `metadata_sep`.
7. Reads the expression matrix (`read.table`, features in rows, samples in columns) and the metadata file, requiring `SampleName` and `Covariate` columns in the latter.
8. Aligns the expression matrix and metadata by intersecting sample names (`colnames` vs `SampleName`), warning if any samples lack matching metadata; requires at least 3 matched samples and at least 2 genes/features.
9. Optionally applies a log2(x + 1) transformation (`log_transform`).
10. Optionally removes zero-variance features across the matched samples (`remove_zero_var`).
11. Computes PCA via `prcomp` on the transposed, (optionally transformed/filtered) matrix.
12. Generates a PC1-vs-PC2 scatter plot, samples colored and labeled by `Covariate`, with a legend and the percentage of variance explained by each component, and writes it to a PDF named `<input_file_basename>_pca.pdf` in `results`.

**Exit behavior**

Exits with status `1` on invalid argument count, invalid `quiet`/`log_transform`/`remove_zero_var`/`threads` values, missing or empty `input_file`/`metadata`, invalid `expr_sep`/`metadata_sep`, missing `SampleName`/`Covariate` metadata columns, no matching samples, or fewer than 3 matched samples / 2 genes. Exits with status `2` if reading the expression matrix or metadata fails, if the PCA computation (`prcomp`) fails, or if writing the output PDF fails. Exits with status `0` once the PCA plot has been generated successfully.

### `run_deseq2.R`

An R script invoked internally by `start.sh` (when `pca_type` is `deseq` or `deseqNormalized`) to compute a DESeq2 variance-stabilized PCA on the raw count matrix, either blind or size-factor/design-aware normalized.

**Usage**

```bash
Rscript run_deseq2.R <input_file> <expr_sep> <metadata> <metadata_sep> <results> <mode> <threads> <quiet>
```

**Arguments**

| Argument | Required | Description |
| :--- | :--- | :--- |
| `input_file` | Yes | Path to the expression/count matrix file. |
| `expr_sep` | Yes | Field separator for the expression matrix (`,`, `;`, `\t`, `tab`). |
| `metadata` | Yes | Path to the sample metadata file. |
| `metadata_sep` | Yes | Field separator used in metadata (`,`, `;`, `\t`, `tab`). |
| `results` | Yes | Output directory for DESeq2 pipeline results (created automatically if missing). |
| `mode` | Yes | Processing mode: `deseq` (blind VST) or `deseqnormalized` (poscounts size-factor VST). |
| `threads` | Yes | Number of parallel threads (positive integer; capped automatically to the available CPU cores; used to register a `BiocParallel::MulticoreParam` backend). |
| `quiet` | Yes | Suppress processing log messages: `true` or `false`. |

**Behavior**

1. Validates argument count (exactly 8 required) and the `quiet` value.
2. Validates `mode` (`deseq`, `deseqnormalized`).
3. Prints the pipeline execution context and validates `threads`, capping it to the available CPU cores if necessary; sets `OMP_NUM_THREADS` and registers a `MulticoreParam` backend for DESeq2.
4. Creates the `results` directory if it does not already exist.
5. Checks that `input_file` and `metadata` exist and are non-empty.
6. Validates and normalizes `expr_sep` and `metadata_sep`.
7. Loads `DESeq2`, `ggplot2`, and `BiocParallel`.
8. Reads the raw count matrix and the metadata file, requiring `SampleName` and `Covariate` columns (matched case-insensitively).
9. Aligns the count matrix and metadata by intersecting sample names, warning if any samples lack matching metadata; requires at least 3 matched samples. Builds a `DESeqDataSetFromMatrix` with design `~ group` (`group` derived from `Covariate`).
10. Depending on `mode`:
    - `deseq`: filters low-count genes (`rowSums(counts) >= 10`), runs a blind Variance Stabilizing Transformation (`vst(dds, blind = TRUE)`), extracts PCA coordinates via `plotPCA`, and saves a PC1-vs-PC2 `ggplot2` scatter plot (colored/labeled by covariate, with percent variance explained) to a PNG named `<input_file_basename>_deseq_pca.png`.
    - `deseqnormalized`: estimates size factors with the `poscounts` method (`estimateSizeFactors(dds, type = "poscounts")`), runs a blind VST on the normalized counts, extracts PCA coordinates via `plotPCA`, and saves the corresponding `ggplot2` scatter plot to a PDF named `<input_file_basename>_deseqNorm_pca.pdf`.

**Exit behavior**

Exits with status `1` on invalid argument count, invalid `quiet`/`mode`/`threads` values, missing or empty `input_file`/`metadata`, invalid `expr_sep`/`metadata_sep`, missing `SampleName`/`Covariate` metadata columns, or fewer than 3 matched samples. Exits with status `2` if loading the required R packages fails, if reading the count matrix or metadata fails, or if the DESeq2 execution (dataset construction, VST, or plot generation) fails for either mode. Exits with status `0` once the PCA plot has been generated successfully.

---

## Docker Image

The image is based on `ubuntu:24.04` and bundles:

* **R** (`r-base`) with `r-cran-data.table`, `r-cran-ggplot2`, and `r-bioc-deseq2` (Bioconductor DESeq2 and its dependencies), for both PCA computation strategies.

`plot_pca.R` and `run_deseq2.R` are copied into `/usr/local/bin` and set as executable; `start.sh` is copied into `/home` and set as executable. The container's default working directory is `/home`, with `bash` as the default `CMD`.