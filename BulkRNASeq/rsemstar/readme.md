# `rsemstar` Workflow

`rsemstar` is a containerized workflow designed to compute gene- and isoform-level expression counts from RNA-Seq FASTQ data using [RSEM](https://github.com/deweylab/RSEM) with [STAR](https://github.com/alexdobin/STAR) as the underlying aligner.

The workflow takes a directory of (optionally gzip-compressed) trimmed FASTQ files, a pre-built combined RSEM/STAR genome index (as produced by the companion [`rsemstarindex`](#) workflow), and a sample metadata file describing which FASTQ file(s) belong to which sample. It validates and loads the metadata, iterates over the samples in Single-End or Paired-End mode, runs `rsem-calculate-expression --star` for each sample, and collects the resulting gene/isoform quantification files, STAR logs, and (optionally) alignment BAM files into the designated output folder (`/results`). An updated metadata file, listing the generated quantification file for each processed sample, is also written to `/results`, ready to be used as input for downstream differential expression analyses.

---

## Container Execution & Usage

The tool is packaged and distributed via GitHub Container Registry (GHCR) under the Docker image:
`ghcr.io/reproduciblebioinformatics/docker4seq-rsemstar-v2:latest`

## Inputs & Configuration Parameters

### File Inputs

* **`metadata`**: CSV or TSV file listing the FASTQ files to process. Expected columns include `SampleName`, `SampleFolder` (optional, for FASTQ files nested in subfolders of `inputDir`), `SampleNumber` (used to pair Single/Paired-End reads and to sort processing order), `Batch`, `Covariate`, and `VisName`.

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
| **`threads`** | Integer indicating the number of CPU cores to be used by the application. |
| **`quiet`** | Set to `true` to suppress tool processing messages; set to `false` to keep verbose logging enabled. |

---

## Implementation Details

The workflow execution logic was generated using the **Baryon** configuration parser and builder. Specifically, the generated Python script (`rsemstar.py`)—derived from the `.bala` specification—was utilized to execute, benchmark, and validate the quantification pipeline across test datasets. The workflow wraps RSEM 1.3.3 and STAR 2.7.11b, both installed inside the container image, and executes `rsem-calculate-expression --star` for each sample against a pre-built ENSEMBL-style combined RSEM/STAR genome index.

**Test command line:**

```bash
python rsemstar.py "./workdir" "./raw_data/fastq_trimmed" "./raw_data/genome_index" "./results" "./raw_data/metadata.csv" "," "reverse" false pe 10 false
```

---
### Manual Docker Launch Example

When running the container manually (i.e., not via a Baryon-generated script), the sample metadata file is **not** automatically placed inside the working directory. You must therefore mount, as `/workDir`, the local folder that actually contains your metadata file, so that the script can locate it at `/workDir/<metadata>`. The FASTQ input directory and the genome index directory can instead be bind-mounted directly, read-only, from their host location.

```bash
docker run --rm \
  -v /path/to/workdir:/workDir \
  -v /path/to/input_fastq_dir:/data_fastq \
  -v /path/to/genome_index_dir:/genome \
  -v /path/to/results_dir:/results \
  ghcr.io/reproduciblebioinformatics/docker4seq-rsemstar-v2:latest \
  bash /home/start.sh /workDir /data_fastq /genome /results /workDir/<metadata> <metadata_sep> <strandness> <save_bam> <seq_type> <threads> <quiet>
```

---

## Auxiliary Scripts

### `start.sh`

The entrypoint script invoked by the container (`bash /home/start.sh ...`). It orchestrates the full pipeline: argument validation, metadata loading, per-sample RSEM/STAR quantification, and output collection.

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

An R validation script invoked internally by `start.sh` before any RSEM/STAR execution begins. It verifies the structural integrity and content of the sample metadata file, preventing the pipeline from running against malformed input.

**Validation checks performed**

1. Confirms the metadata file exists and is not empty.
2. Confirms the specified separator is actually present in the header line.
3. Rejects the file if it contains blank lines.
4. Confirms the presence of all expected columns: `SampleName`, `SampleFolder`, `SampleNumber`, `Batch`, `Covariate`, `VisName`.
5. Rejects missing/empty values in the required columns `SampleName`, `SampleNumber`, `Covariate`, `VisName`.
6. Validates the `Batch` column, allowing either a populated value or an explicit `NA`/`N/A` placeholder (case-insensitive); truly empty cells are rejected.
7. If `SEQ_TYPE` is provided, validates the frequency of `SampleNumber` values: exactly one occurrence per sample for `se` mode, exactly two occurrences per sample for `pe` mode.

**Exit behavior**

The script exits with status `0` on successful validation, and also when `-h`/`--help` is passed or fewer than two arguments are supplied (usage message only, not treated as an error by this script). On any validation failure, it exits with status `1`, causing `start.sh` to terminate the pipeline before any RSEM/STAR processing occurs.

---

## Docker Image

The image is based on `ubuntu:24.04` and bundles:

* **R** (base) and **Perl**, required respectively by `check_samplemetadata.R` and by RSEM's Perl-based utility scripts.
* **RSEM 1.3.3**, installed under `/usr/local/bin/RSEM-1.3.3` and added to `PATH`.
* **STAR 2.7.11b**, extracted from source archive and installed as `/usr/local/bin/STAR`.

`check_samplemetadata.R` is copied into `/usr/local/bin` and set as executable; `start.sh` is copied into `/home` and set as executable. The container's default working directory is `/home`, with `bash` as the default `CMD`.