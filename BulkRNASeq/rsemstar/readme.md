# `rsemstar` Workflow

`rsemstar` is a containerized workflow designed to compute gene- and isoform-level expression counts from RNA-Seq FASTQ data using [RSEM](https://github.com/deweylab/RSEM) with [STAR](https://github.com/alexdobin/STAR) as the underlying aligner.

The workflow takes a directory of (optionally gzip-compressed) trimmed FASTQ files, a pre-built combined RSEM/STAR genome index (as produced by the companion [`rsemstarindex`](#) workflow), and a sample metadata file describing which FASTQ file(s) belong to which sample. It validates and loads the metadata, iterates over the samples in Single-End or Paired-End mode, runs `rsem-calculate-expression --star` for each sample, and collects the resulting gene/isoform quantification files, STAR logs, and (optionally) alignment BAM files into the designated output folder (`outDir`). An updated metadata file, listing the generated quantification file for each processed sample, is also written to `outDir`, ready to be used as input for downstream differential expression analyses.

---

## Container Execution & Usage

The tool is packaged and distributed via GitHub Container Registry (GHCR) under the Docker image:
`ghcr.io/reproduciblebioinformatics/docker4seq-rsemstar-v2:latest`

Execution is driven by a wrapper script generated from the `rsemstar.bala` specification via [**Baryon**](https://github.com/Fairflow-BioinformaticsFramework/Baryonlang), Fairflow's `.bala`-to-source-code generator. Baryon translates the `.bala` specification into an equivalent runnable script in the target language (Python, R, etc.), which validates the inputs, prepares an isolated scratch working directory, copies every file declared with `flag=cp` in the `.bala` spec (`metadata`) into it, assembles the corresponding `docker run` command from the `.bala` `usage` template, and finally executes it. See the [Baryon repository](https://github.com/Fairflow-BioinformaticsFramework/Baryonlang) for details on installing Baryon and generating the wrapper script for your language of choice.

### Command Syntax

```bash
python rsemstar.py <workdir> <inputDir> <genomeDir> <outDir> <metadata> <metadata_sep> <strandness> <save_bam> <seq_type> <threads> <quiet>
```

### Manual Docker Execution

Users who prefer to skip the Baryon-generated wrapper can invoke the container directly with `docker run`. In that case, the `flag=cp` input (`metadata`) must be copied (or bind-mounted) into the `/workDir` mount beforehand, since `start.sh` expects plain filesystem paths, not host paths outside the container. The `flag=in` inputs (`inputDir`, `genomeDir`) can instead be bind-mounted directly, read-only, from their host location:

```bash
docker run --rm \
  -v /path/to/workdir:/workDir \
  -v /path/to/input_fastq_dir:/data_fastq \
  -v /path/to/genome_index_dir:/genome \
  -v /path/to/results_dir:/results \
  ghcr.io/reproduciblebioinformatics/docker4seq-rsemstar-v2:latest \
  bash /home/start.sh /workDir /data_fastq /genome /results /workDir/<metadata> <metadata_sep> <strandness> <save_bam> <seq_type> <threads> <quiet>
```

where `<metadata>` is the name of the metadata file previously copied into `/path/to/workdir` on the host (so that it appears under `/workDir` inside the container). See the [`start.sh`](#startsh) section below for the full argument reference.

---

## Directory Mounts (Volume Mapping)

| Mount Point | Flag | Description |
| :--- | :--- | :--- |
| `/workDir` | `io` | Working folder for execution and temporary file storage. In the Baryon-generated workflow this is mapped to an auto-numbered `<workdir>/scratchN` folder, into which the `flag=cp` file (`metadata`) is copied before the container starts; when running manually, the same file must be copied here by hand. |
| `/data_fastq` | `in` | Read-only directory containing the (optionally gzip-compressed) trimmed FASTQ files referenced by `metadata`. No files are copied here by Baryon, since `inputDir` uses `flag=in`. |
| `/genome` | `in` | Read-only directory containing the pre-built combined RSEM/STAR genome index. IMPORTANT: only genomic indexes built from an ENSEMBL genome and the corresponding GTF (e.g. via the `rsemstarindex` workflow) are supported. |
| `/results` | `out` | Scratch/destination directory where the container is mounted and the RSEM gene/isoform quantification results are written. In the Baryon-generated workflow this is mapped to an auto-numbered `<outdir>/outputN` folder. |

---

## Inputs & Configuration Parameters

### File Inputs

* **`metadata`** (`flag: cp`): CSV or TSV file listing the FASTQ files to process. Expected columns include `SampleName`, `SampleFolder` (optional, for FASTQ files nested in subfolders of `inputDir`), `SampleNumber` (used to pair Single/Paired-End reads and to sort processing order), `Batch`, `Covariate`, and `VisName`. Accepts any plain-text file using a consistent field separator.

### Command-line Parameters

| Parameter | Description |
| :--- | :--- |
| **`workdir`** | Scratch workspace directory for temporary RSEM/STAR processing. If missing or not a valid directory, it defaults to `outDir`. |
| **`inputDir`** | Base directory containing the (optionally gzip-compressed) trimmed FASTQ files referenced by `metadata`. |
| **`genomeDir`** | Directory containing the pre-built combined STAR/RSEM reference genome index (see the `rsemstarindex` workflow). |
| **`outDir`** | Output directory for the final gene/isoform quantification results. Must exist and be empty. |
| **`metadata`** | Path to the metadata file containing sample names, sample numbers, and optional sample subfolders. |
| **`metadata_sep`** | Field separator used in `metadata`. Allowed values: `,`, `;`, `\t`, `tab` (case-insensitive). |
| **`strandness`** | Type of sequencing protocol used for the analysis. Allowed values: `none` (no strand selection), `forward` (standard Illumina strandness protocol), `reverse` (ACCESS Illumina protocol). |
| **`save_bam`** | Boolean indicating whether the genome and transcriptome alignment BAM files should be kept in `outDir`. Allowed values: `true`, `false`. |
| **`seq_type`** | Type of reads to be processed. Allowed values: `se` (Single-End), `pe` (Paired-End). |
| **`threads`** | Integer indicating the number of CPU cores to be used by the application (default: `10`). Requests exceeding available CPU cores are automatically capped. |
| **`quiet`** | Set to `true` to suppress tool `INFO`/`PROCESS` log messages; set to `false` to keep verbose logging enabled (default: `false`). Warnings, errors, and success messages are always shown regardless of this setting. |

---

## Implementation Details

The workflow execution logic was generated using [**Baryon**](https://github.com/Fairflow-BioinformaticsFramework/Baryonlang), Fairflow's configuration parser and code builder. Specifically, the generated Python script (`rsemstar.py`)—derived from the `rsemstar.bala` specification—was used to execute, benchmark, and validate the quantification pipeline. Baryon can regenerate the equivalent wrapper in other supported target languages directly from the same `.bala` file; refer to the Baryon repository for the list of supported languages and generation instructions. The workflow wraps [RSEM](https://github.com/deweylab/RSEM) 1.3.3 and [STAR](https://github.com/alexdobin/STAR) 2.7.11b, both installed inside the container image, and executes `rsem-calculate-expression --star` for each sample (or Single/Paired-End sample pair) to produce gene- and isoform-level quantification against a pre-built ENSEMBL-style combined RSEM/STAR genome index.

**Test command line:**

```bash
python rsemstar.py "./workdir" "./raw_data/fastq_trimmed" "./raw_data/genome_index" "./results" "./raw_data/metadata.csv" "," "reverse" false pe 10 false
```

---

## Auxiliary Scripts

### `start.sh`

The entrypoint script invoked inside the container (`bash /home/start.sh ...`), launched either by the Baryon-generated wrapper or manually via `docker run`. It orchestrates the full in-container pipeline: argument validation, metadata loading, per-sample RSEM/STAR quantification, and output collection.

**Usage**

```bash
bash start.sh <workdir> <inputDir> <genomeDir> <outDir> <metadata> <metadata_sep> <strandness> <save_bam> <seq_type> <threads> <quiet>
```

**Arguments**

| Argument | Required | Description |
| :--- | :--- | :--- |
| `workdir` | Yes | Scratch workspace directory for temporary RSEM processing. If missing or invalid, falls back to `outDir`. |
| `inputDir` | Yes | Base directory containing raw or structured FASTQ files. Must exist and contain at least one file. |
| `genomeDir` | Yes | Directory containing the STAR/RSEM reference genome index. Must contain `genomeParameters.txt` and at least one `*.seq` file. |
| `outDir` | Yes | Output directory for final quantification results. Must exist and be empty. |
| `metadata` | Yes | Path to the metadata file containing sample names and numbers. Must exist. |
| `metadata_sep` | Yes | Field separator used in `metadata`: `,`, `;`, `tab`, or `\t` (case-insensitive). |
| `strandness` | Yes | Strand specificity: `none`, `forward`, or `reverse`. |
| `save_bam` | Yes | Save aligned BAM files: `true` or `false`. Unrecognized values fall back to `false` with a warning. |
| `seq_type` | Yes | Sequencing type: `se` (Single-End) or `pe` (Paired-End). |
| `threads` | Yes | Number of parallel threads (positive integer; requests exceeding available CPU cores are capped automatically). |
| `quiet` | Yes | Set to `true` to suppress `INFO`/`PROCESS` log messages; set to `false` for verbose logging. |

**Execution flow**

1. Validates argument count (exactly 11 required) and the `quiet` value (`true`/`false`).
2. Validates `threads` (must be a positive integer; requests exceeding available CPU cores are capped with a warning).
3. Checks that `outDir` exists and is empty.
4. Checks that `inputDir` exists and contains at least one file.
5. Checks that `genomeDir` exists and contains a valid combined STAR/RSEM index (`genomeParameters.txt` and at least one `*.seq` file).
6. Resolves `workdir`: if missing or not a valid directory, defaults to `outDir`.
7. Checks that the `metadata` file exists.
8. Validates and normalizes `metadata_sep`.
9. Validates `strandness` and `seq_type`; validates `save_bam` (defaulting to `false` with a warning if unrecognized).
10. Validates the metadata content via `check_samplemetadata.R`, including required columns and, given `seq_type`, `SampleNumber` frequency consistency.
11. Loads the metadata into memory and sorts samples by `SampleNumber`.
12. For each sample (Single-End) or matched `SampleNumber` pair (Paired-End), runs `rsem-calculate-expression --star` to align and quantify; on success, collects `*.genes.results`, `*.isoforms.results`, and the STAR `Log.final.out` into `outDir` (plus alignment BAM files if `save_bam` is `true`), and appends the sample to an updated metadata file. Samples with missing FASTQ files, mismatched Paired-End pairs, or failed RSEM runs are skipped with a warning/error and do not stop the pipeline.
13. Saves the updated metadata file (suffixed `_rsemstar`) to `outDir`, removes temporary files, and reports success or a partial-failure summary.

**Exit behavior**

Exits with status `1` on invalid arguments, `quiet`, `threads`, `strandness`, or `seq_type` values, a missing/non-empty `outDir`, a missing/empty `inputDir`, an invalid/missing `genomeDir` index, a missing `metadata` file, an invalid `metadata_sep`, a missing `SampleName`/`SampleNumber` column in `metadata`, or when no `*.genes.results` output file was produced. Exits with status `2` if metadata content validation via `check_samplemetadata.R` fails. Exits with status `1` if one or more samples failed or were skipped during RSEM/STAR processing (while still keeping the outputs generated for the successfully processed samples). Exits with status `0` once RSEM/STAR quantification has completed successfully for all samples.

### `check_samplemetadata.R`

An R script invoked internally by `start.sh` to validate the structure and content of the sample metadata file before processing begins.

**Usage**

```bash
Rscript check_samplemetadata.R <METADATA_FILE> <SEPARATOR> [SEQ_TYPE]
```

**Arguments**

| Argument | Required | Description |
| :--- | :--- | :--- |
| `METADATA_FILE` | Yes | Path to the metadata CSV/TSV file. |
| `SEPARATOR` | Yes | Field separator used in the file, e.g. `;` or `,`. |
| `SEQ_TYPE` | No | Optional mode: `se` (Single-End) or `pe` (Paired-End), used to cross-check `SampleNumber` frequency. |

**Behavior**

1. Validates that at least `METADATA_FILE` and `SEPARATOR` were provided.
2. Checks that the metadata file exists and is not empty.
3. Verifies the specified separator is present in the header line.
4. Checks for empty lines in the raw file.
5. Parses the metadata into a data frame using the given separator.
6. Checks that all expected columns are present: `SampleName`, `SampleFolder`, `SampleNumber`, `Batch`, `Covariate`, `VisName`.
7. Checks that `SampleName`, `SampleNumber`, `Covariate`, and `VisName` contain no missing/empty values.
8. Validates the `Batch` column: empty values are only accepted when expressed as `NA`/`N/A` (case-insensitive); any other empty value is rejected.
9. If `SEQ_TYPE` is provided, checks `SampleNumber` frequency consistency: each value must be unique in `se` mode, or appear exactly twice in `pe` mode.

**Exit behavior**

Exits with status `0` on successful validation, and also when `-h`/`--help` is passed or fewer than two arguments are supplied (usage message only, not treated as an error by this script). Exits with status `1` on any validation failure: missing/empty file, separator not found in the header, empty lines in the file, missing expected column(s), missing/empty values in required columns, invalid `Batch` values, or a `SampleNumber` frequency inconsistent with `SEQ_TYPE`.

---

## Docker Image

The image is based on `ubuntu:24.04` and bundles:

* **R** (base) and **Perl**, required respectively by `check_samplemetadata.R` and by RSEM's Perl-based utility scripts.
* **RSEM 1.3.3**, installed under `/usr/local/bin/RSEM-1.3.3` and added to `PATH`.
* **STAR 2.7.11b**, extracted from source archive and installed as `/usr/local/bin/STAR`.

`check_samplemetadata.R` is copied into `/usr/local/bin` and set as executable; `start.sh` is copied into `/home` and set as executable. The container's default working directory is `/home`, with `bash` as the default `CMD`.