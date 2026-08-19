# `annotation` Workflow

`annotation` is a containerized workflow designed to annotate and aggregate RSEM quantification outputs (`*.genes.results` / `*.isoforms.results`) produced by RNA-Seq quantification pipelines.

The workflow takes a directory of per-sample RSEM result files, a reference gene annotation file (GTF/GFF3, typically sourced from ENSEMBL), and a sample metadata sheet, and produces a set of gene- and isoform-level expression matrices (raw counts, FPKM, TPM, and log2-transformed FPKM/TPM) annotated with gene symbols/names and optionally filtered by Ensembl gene biotype. Gene ID-to-symbol mapping is first extracted from the annotation file, then used to annotate and aggregate all RSEM outputs listed in the metadata sheet into unified expression tables. The resulting flat text tables, an `.Rda` binary bundle, and an updated metadata file (with renamed sample columns) are written directly to the designated output folder (`outDir`).

---

## Container Execution & Usage

The tool is packaged and distributed via GitHub Container Registry (GHCR) under the Docker image:
`ghcr.io/reproduciblebioinformatics/docker4seq-annotation-v2:latest`

Execution is driven by a wrapper script generated from the `annotation.bala` specification via [**Baryon**](https://github.com/Fairflow-BioinformaticsFramework/Baryonlang), Fairflow's `.bala`-to-source-code generator. Baryon translates the `.bala` specification into an equivalent runnable script in the target language (Python, R, etc.), which validates the inputs, prepares an isolated scratch working directory, copies every file declared with `flag=cp` in the `.bala` spec (`annotation_file`, `metadata`) into it, assembles the corresponding `docker run` command from the `.bala` `usage` template, and finally executes it. See the [Baryon repository](https://github.com/Fairflow-BioinformaticsFramework/Baryonlang) for details on installing Baryon and generating the wrapper script for your language of choice.

### Command Syntax

```bash
python annotation.py <workdir> <input_dir> <outdir> <annotation_file> <gene_biotype> <metadata> <metadata_sep> <threads> <quiet>
```

### Manual Docker Execution

Users who prefer to skip the Baryon-generated wrapper can invoke the container directly with `docker run`. In that case, the `flag=cp` inputs (`annotation_file`, `metadata`) must be copied (or bind-mounted) into the `/workDir` mount beforehand, since `start.sh` expects plain filesystem paths, not host paths outside the container:

```bash
docker run --rm \
  -v /path/to/workdir:/workDir \
  -v /path/to/rsem_results:/data_results \
  -v /path/to/results_dir:/results \
  ghcr.io/reproduciblebioinformatics/docker4seq-annotation-v2:latest \
  bash /home/start.sh /workDir /data_results /results /workDir/<annotation_file> <gene_biotype> /workDir/<metadata> <metadata_sep> <threads> <quiet>
```

where `<annotation_file>` and `<metadata>` are the names of the GTF/GFF3 and metadata files previously copied into `/path/to/workdir` on the host (so that they appear under `/workDir` inside the container), and `/path/to/rsem_results` contains the per-sample `*.genes.results` / `*.isoforms.results` files. See the [`start.sh`](#startsh) section below for the full argument reference.

---

## Directory Mounts (Volume Mapping)

| Mount Point | Flag | Description |
| :--- | :--- | :--- |
| `/workDir` | `io` | Working folder for execution and temporary/cache file storage (e.g. the gene annotation mapping cache). In the Baryon-generated workflow this is mapped to an auto-numbered `<workdir>/scratchN` folder, into which every `flag=cp` file (`annotation_file`, `metadata`) is copied before the container starts; when running manually, the same files must be copied here by hand. |
| `/data_results` | `in` | Directory containing the per-sample RSEM quantification outputs (`*.genes.results` / `*.isoforms.results`) to be annotated and aggregated. |
| `/results` | `out` | Scratch/destination directory where the container is mounted and the annotated, aggregated expression tables are written. In the Baryon-generated workflow this is mapped to an auto-numbered `<outdir>/outputN` folder. Must exist and be empty. |

---

## Inputs & Configuration Parameters

### File Inputs

* **`annotation_file`** (`flag: cp`): Reference gene annotation file (GTF or GFF3 format), used to map `gene_id` values to gene names/symbols and Ensembl gene biotypes.
* **`metadata`** (`flag: cp`): A CSV or TSV file containing sample metadata for the files located in `input_dir`. Must include a sample-name column (`SampleName`, `sample_name`, or `sample`, case-insensitive) whose values correspond to (or can be mapped to) the `*.genes.results` file names in `input_dir`. Optional columns `VisName`/`SampleID`/`id`, `Covariate`/`Condition`/`Group`, and `Batch` (also case-insensitive) are used to build a human-readable, unique display name for each sample. Must describe at least 2 samples.

### Command-line Parameters

| Parameter | Description |
| :--- | :--- |
| **`inputDir`** | Directory containing the RSEM per-sample result files (`*.genes.results`, `*.isoforms.results`). |
| **`outDir`** | Output directory for the generated, annotated expression tables. Must exist and be empty. |
| **`annotation_file`** | Path to the reference annotation file (GTF or GFF3). |
| **`gene_biotype`** | Ensembl gene biotype used both to build the gene mapping and to filter the aggregated expression matrices (e.g. `protein_coding`, `lincRNA`, `miRNA`, ...), or `all` to skip biotype-based filtering during aggregation. |
| **`metadata`** | Path to the sample metadata file (CSV/TSV) listing sample names and, optionally, visualization names, covariates, and batches. |
| **`metadata_sep`** | Field separator used in the metadata file. Allowed values: `,`, `;`, `\t`, `tab` (case-insensitive). |
| **`threads`** | Integer indicating the number of CPU cores to be used by the application (default: `10`). Requests exceeding available CPU cores are automatically capped. |
| **`quiet`** | Set to `true` to suppress tool `INFO`/`PROCESS` log messages; set to `false` to keep verbose logging enabled. Warnings, errors, and success messages are always shown regardless of this setting. |

---

## Implementation Details

The workflow execution logic was generated using [**Baryon**](https://github.com/Fairflow-BioinformaticsFramework/Baryonlang), Fairflow's configuration parser and code builder. Specifically, the generated Python script (`annotation.py`)—derived from the `annotation.bala` specification—was used to execute, benchmark, and validate the annotation pipeline. Baryon can regenerate the equivalent wrapper in other supported target languages directly from the same `.bala` file; refer to the Baryon repository for the list of supported languages and generation instructions. The workflow is implemented entirely in R (base + `data.table`), with no external bioinformatics binaries: it parses the reference GTF/GFF3 annotation to build a gene-id-to-symbol/biotype mapping table, then uses it to annotate and aggregate the RSEM `*.genes.results` / `*.isoforms.results` files listed in the metadata sheet into unified, biotype-filtered expression matrices (raw counts, FPKM, TPM, log2FPKM, log2TPM) at both gene and isoform level.

**Test command line:**

```bash
python annotation.py "./workdir" "./data_results" "./results" "./raw_data/annotation.gtf" "protein_coding" "./raw_data/metadata.csv" "," 10 false
```

---

## Auxiliary Scripts

### `start.sh`

The entrypoint script invoked inside the container (`bash /home/start.sh ...`), launched either by the Baryon-generated wrapper or manually via `docker run`. It orchestrates the full in-container pipeline: argument validation, gene mapping extraction from the annotation file, and annotated expression matrix aggregation.

**Usage**

```bash
bash start.sh <input_dir> <results> <annotation_file> <gene_biotype> <metadata> <metadata_sep> <threads> <quiet>
```

**Arguments (all mandatory)**

| Argument | Description |
| :--- | :--- |
| `input_dir` | Directory containing RSEM results files (`*.genes.results`). Must exist and contain at least one matching file. |
| `results` | Output directory for aggregated expression tables. Must exist and be empty. |
| `annotation_file` | Path to reference annotation GTF/GFF3 file. Must exist. |
| `gene_biotype` | Filtering Ensembl biotype, or `all` to skip filtering. Must not be empty. |
| `metadata` | Path to the metadata file containing sample names and folders. Must exist. |
| `metadata_sep` | Field separator used in metadata (`,`, `;`, `\t`, or `tab`, case-insensitive). |
| `threads` | Number of parallel threads (positive integer; capped automatically to the available CPU cores). |
| `quiet` | Suppress processing log messages: `true` or `false`. |

**Execution flow**

1. Validates argument count (exactly 9 required) and the `quiet` value (`true`/`false`).
2. Prints the pipeline execution context (working/input/results directories, annotation file, biotype, metadata, separator, threads, quiet mode).
3. Validates `threads` (must be a positive integer; requests exceeding available CPU cores are capped with a warning) and exports it as `OMP_NUM_THREADS`.
4. Checks that `workdir` exists, that `results` exists and is empty, that `input_dir` exists, that `annotation_file` exists, and that `metadata` exists.
5. Validates and normalizes `metadata_sep` (accepts `,`, `;`, `tab`, `\t`, case-insensitive).
6. Validates that `gene_biotype` is not empty.
7. Verifies that at least one `*.genes.results` file is present in `input_dir`.
8. **Step 1:** Runs `extract_gene_mapping.R` on `annotation_file`/`gene_biotype`, writing a gene-mapping cache file (`gene_annotation_map.tsv`) into `workdir`.
9. **Step 2:** Runs `generate_expression_tables.R` on `metadata`, `metadata_sep`, `input_dir`, `results`, `gene_biotype`, and the gene-mapping cache file, producing the final aggregated, annotated expression tables in `results`.
10. Reports success or, on failure of either step, aborts with the corresponding exit code.

**Exit behavior**

Exits with status `1` on invalid/missing arguments, invalid `quiet`/`threads`/`metadata_sep`/`gene_biotype` values, missing or non-empty directories, missing `annotation_file`/`metadata`, or no `*.genes.results` files found in `input_dir`. Exits with status `2` if `extract_gene_mapping.R` fails. Exits with status `3` if `generate_expression_tables.R` fails. Exits with status `0` and a success message once the annotated expression tables have been generated.

### `extract_gene_mapping.R`

An R script invoked internally by `start.sh` to parse the reference annotation file and build a sanitized gene-id-to-symbol/biotype mapping table.

**Usage**

```bash
Rscript extract_gene_mapping.R <gtf_path> <target_biotype> <output_path> <threads> <quiet>
```

**Arguments (all mandatory)**

| Argument | Description |
| :--- | :--- |
| `gtf_path` | Path to the reference GTF annotation file. |
| `target_biotype` | Target gene biotype filter (e.g. `protein_coding`). |
| `output_path` | Output path for the generated TSV mapping file. |
| `threads` | Number of parallel threads (positive integer), used to configure `data.table` multithreading. |
| `quiet` | Suppress processing log messages: `true` or `false`. |

**Behavior**

1. Validates the argument count, the `quiet` value, the `threads` value (positive integer), and that `gtf_path` exists.
2. Reads the GTF file line by line and discards comment lines (starting with `#`).
3. Splits each data line into its 9 tab-separated GTF columns and extracts the `gene_biotype`, `gene_id`, and `gene_name` attributes from the 9th (attributes) column.
4. Filters rows whose `gene_biotype` matches `target_biotype`, then discards rows with a missing/empty `gene_id`.
5. Builds a 3-column table (`gene_id`, `gene_name`, `gene_biotype`), replacing missing/empty `gene_name` values with `"N/A"`.
6. Detects and logs (as warnings) `gene_id` values that map to more than one distinct `gene_name` ("anomalies"), without discarding them.
7. Deduplicates rows by `gene_id` (preferring rows with a known, non-`"N/A"` `gene_name` and the original row order), then writes the resulting mapping table to `output_path` as a tab-separated TSV file with header.
8. Prints a processing summary (lines read, lines matching biotype, unique `gene_id`s written, skipped lines, anomalies detected) unless `quiet` is `true`.

**Exit behavior**

Exits with status `1` on invalid arguments, an invalid `quiet` value, an invalid `threads` value, or a missing `gtf_path`. Exits with status `2` if the GTF file cannot be read, does not contain 9 tab-separated columns, or the output TSV file cannot be written. Exits with status `0` once the mapping file has been successfully generated.

### `generate_expression_tables.R`

An R script invoked internally by `start.sh` to annotate and aggregate the per-sample RSEM gene- and isoform-level quantifications listed in the metadata sheet into unified expression matrices, using the mapping file produced by `extract_gene_mapping.R`.

**Usage**

```bash
Rscript generate_expression_tables.R <metadata_file> <separator> <input_dir> <output_dir> <bio_type> <mapping_tsv>
```

**Arguments (all mandatory)**

| Argument | Description |
| :--- | :--- |
| `metadata_file` | Path to the CSV/TSV metadata file containing sample names and, optionally, visualization names, covariates, and batches. |
| `separator` | Delimiter used in the metadata file (e.g. `,`, `;`, `\t`). |
| `input_dir` | Directory containing the RSEM `*.genes.results` / `*.isoforms.results` files. |
| `output_dir` | Output directory for the aggregated expression tables (created if it does not already exist). |
| `bio_type` | Ensembl biotype used to filter the aggregated gene matrices, or `all` to skip filtering. |
| `mapping_tsv` | 3-column gene mapping file (`gene_id`, `gene_name`, `gene_biotype`) produced by `extract_gene_mapping.R`. |

**Behavior**

1. Validates the argument count and creates `output_dir` if missing.
2. Loads `metadata_file` using `separator`, identifying the sample-name column (`SampleName`/`sample_name`/`sample`, case-insensitive; mandatory) and, if present, the visualization-name (`VisName`/`SampleID`/`id`), covariate (`Covariate`/`Condition`/`Group`), and batch (`Batch`) columns (all case-insensitive). Requires at least 2 samples.
3. Builds a unique display name for each sample by combining the visualization name (or sample name) with the covariate and batch values, when available.
4. **Step 1:** Resolves, for every sample, the corresponding `*.genes.results` and `*.isoforms.results` file paths in `input_dir`, and scans all of them to build the ground-truth union of `gene_id` and `transcript_id` values actually quantified across the whole experiment.
5. **Step 2:** Loads `mapping_tsv` and joins it to the discovered `gene_id` list; genes without a mapped name fall back to using their `gene_id` as name, and genes without a mapped biotype are labeled `"unknown"`. If `bio_type` is not `"all"`, the gene set is further filtered to only the requested biotype.
6. **Step 3:** For each sample, extracts gene-level `expected_count` (rounded), `FPKM`, and `TPM` values aligned to the reference gene set, imputing missing genes with `0` and logging a warning with the count of imputed genes per sample.
7. **Step 4:** For each sample, extracts isoform-level `expected_count` (rounded), `FPKM`, and `TPM` values aligned to the reference isoform set, with the same imputation/warning logic.
8. **Step 5:** Writes the aggregated results to `output_dir`:
   - `experiment_experiment.tables.Rda`: R binary bundle containing the `counts`, `fpkm`, `tpm`, `counts.iso`, `fpkm.iso`, `tpm.iso` data frames (row names set to `gene_id:gene_name` for gene-level tables and `transcript_id` for isoform-level tables).
   - `experiment_counts.txt`, `experiment_log2FPKM.txt`, `experiment_log2TPM.txt`: flat, tab-separated gene-level matrices (raw counts, and log2(FPKM+1)/log2(TPM+1)), keyed by `gene_id:gene_name`.
   - `experiment_isoforms_counts.txt`, `experiment_isoforms_log2FPKM.txt`, `experiment_isoforms_log2TPM.txt`: flat, tab-separated isoform-level matrices, keyed by `transcript_id`.
   - An updated metadata file (same columns and separator as the input, with the sample-name column replaced by the computed display names), written to `output_dir` under a name derived from the input metadata file name, with the last `_`-separated segment (or, if none, a plain suffix) replaced by `annotated`.
9. Prints a compilation summary (samples processed, compiled gene/isoform entries, updated metadata path, and total gene/isoform anomalies detected across all samples).

**Exit behavior**

Exits with status `1` if fewer than 6 arguments are provided, the sample-name column cannot be found in the metadata, or fewer than 2 samples are described. Exits with status `2` if `metadata_file` does not exist. Reports (without hard-terminating the script at that point) if `mapping_tsv` does not exist, individual `*.genes.results`/`*.isoforms.results` files are missing, or genes/isoforms are missing from a given sample (imputed with `0` and logged as anomalies). Completes with an implicit successful (`0`) exit status once all matrices and the updated metadata file have been written.

---

## Docker Image

The image is based on `ubuntu:24.04` and bundles:

* **R** (base + `r-cran-data.table`) for the mapping-extraction and aggregation scripts.

`extract_gene_mapping.R` and `generate_expression_tables.R` are copied into `/usr/local/bin` and set as executable. `start.sh` is copied into `/home` and set as executable. The container's default working directory is `/home`, with `bash` as the default `CMD`.