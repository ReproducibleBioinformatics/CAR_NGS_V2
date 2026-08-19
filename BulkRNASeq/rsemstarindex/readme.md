# `rsemstarindex` Workflow

`rsemstarindex` is a containerized workflow designed to automate the generation of RSEM/STAR genome reference indexes for RNA-Seq quantification pipelines.

The workflow takes a reference genome FASTA file and a gene annotation GTF file (typically sourced from ENSEMBL), optionally applies a genome filtering strategy to remove mitochondrial sequences and/or long-name scaffolds/contigs, and then builds the combined [RSEM](https://github.com/deweylab/RSEM)/[STAR](https://github.com/alexdobin/STAR) reference index via `rsem-prepare-reference --star`. Both the FASTA and GTF inputs may be provided either as plain-text or gzip-compressed (`.gz`) files. The resulting index files are written directly to the designated output folder (`/results`), ready to be used as input for downstream STAR alignment and RSEM quantification steps.

---

## Container Execution & Usage

The tool is packaged and distributed via GitHub Container Registry (GHCR) under the Docker image:
`ghcr.io/reproduciblebioinformatics/docker4seq-rsemstarindex-v2:latest`

## Inputs & Configuration Parameters

### File Inputs

* **`fastafile`**: Path to the input genome FASTA file (`.fa` or `.fa.gz`), containing the raw DNA sequence (chromosomes) of the reference genome, used by STAR as the blueprint for alignment.
* **`gtffile`**: Path to the input gene annotation GTF file (`.gtf` or `.gtf.gz`), containing the gene annotations (coordinates of exons, introns, and transcripts), used by RSEM to quantify gene expression.

### Command-line Parameters

| Parameter | Description |
| :--- | :--- |
| **`outDir`** | Output directory for the generated RSEM/STAR genome index. Must exist and be empty. |
| **`fastafile`** | Path to the input genome FASTA file passed to the script. |
| **`gtffile`** | Path to the input gene annotation GTF file passed to the script. |
| **`filter`** | Genome filtering strategy applied prior to indexing. Allowed values: `none` (no filtering), `all` (removes mitochondrial DNA and long-name/non-standard scaffolds), `mito` (removes mitochondrial DNA only), `chrom` (removes long-name/non-standard scaffolds only). |
| **`chrom_pattern`** | Optional regex to override the default chromosome-naming pattern used to identify main chromosomes when `filter` is `all` or `chrom`. Leave empty or pass `null` to keep the default pattern. |
| **`threads`** | Integer indicating the number of CPU cores to be used by the application. |
| **`quiet`** | Set to `true` to suppress tool processing messages; set to `false` to keep verbose logging enabled. |

---

## Implementation Details

The workflow execution logic was generated using the **Baryon** configuration parser and builder. Specifically, the generated Python script (`rsemstarindex.py`)—derived from the `.bala` specification—was utilized to execute, benchmark, and validate the indexing pipeline across test datasets. The `raw_data` directory contains the datasets used for testing. The workflow wraps RSEM 1.3.3 and STAR 2.7.11b, both installed inside the container image.

**Test command line:**

```bash
python rsemstarindex.py "./workdir" "./results" "./raw_data/genome.fa.gz" "./raw_data/annotation.gtf.gz" all null 10 false
```

---
### Manual Docker Launch Example

When running the container manually (i.e., not via a Baryon-generated script), the `fastafile` and `gtffile` inputs are **not** automatically placed inside the working directory. You must therefore mount, as `/workDir`, the local folder that actually contains your genome FASTA and GTF files, so that the script can locate them at `/workDir/<fastafile>` and `/workDir/<gtffile>`.

```bash
docker run --rm \
  -v /path/to/workdir:/workDir \
  -v /path/to/results_dir:/results \
  ghcr.io/reproduciblebioinformatics/docker4seq-rsemstarindex-v2:latest \
  bash /home/start.sh /results /workDir/<fastafile> /workDir/<gtffile> <filter> <chrom_pattern> <threads> <quiet>
```

---

## Auxiliary Scripts

### `start.sh`

The entrypoint script invoked by the container (`bash /home/start.sh ...`). It orchestrates the full pipeline: argument validation, input decompression, optional genome filtering, and RSEM/STAR reference index generation.

**Execution flow**

1. Validates argument count and the `quiet` value (`true`/`false`).
2. Validates `threads` (must be a positive integer; requests exceeding available CPU cores are capped with a warning).
3. Checks that `outDir` exists and is empty, and that both `fastafile` and `gtffile` exist.
4. Validates the `filter` value (`none`, `all`, `mito`, `chrom`).
5. Decompresses `fastafile` and `gtffile` into a temporary working folder if they are gzip-compressed (`.gz`), otherwise copies them as-is.
6. Depending on `filter`:
   * `none`: skips all filtering steps.
   * `all` or `mito`: runs `remove_mitochondrion.R` to strip mitochondrial sequences from the FASTA (a "no mitochondrial sequence found" result is treated as a non-fatal warning).
   * `all` or `chrom`: runs `filter_chromosomes.R` to retain only main chromosomes/scaffolds, based on `chrom_pattern` if provided, or the default naming pattern otherwise.
7. Aborts the pipeline (cleaning up temporary files) if any filtering step fails.
8. Runs `rsem-prepare-reference --star` on the (optionally filtered) FASTA and GTF files, writing the resulting `genome.*` index files into `outDir`.
9. Removes temporary decompressed files and reports success or failure.

**Exit behavior**

Exits with status `1` on any parameter, path, filter-value, or filtering-step failure. Exits with a non-zero status inherited from `rsem-prepare-reference` if it fails. Exits with status `0` and a success message once the RSEM/STAR index has been generated.

### `remove_mitochondrion.R`

An R script invoked internally by `start.sh` (when `filter` is `all` or `mito`) to remove mitochondrial sequences from the genome FASTA file before indexing.

**Validation checks performed**

1. Confirms the FASTA file exists and that the `quiet` value is `true`/`false`.
2. Loads the FASTA file via `Biostrings::readDNAStringSet`.
3. Searches sequence names for mitochondrial identifiers matching `^MT|^mitochondrion|^M$` (case-insensitive).
4. If matches are found, removes them and overwrites the FASTA file with the filtered sequence set.
5. If no mitochondrial sequence is found, leaves the FASTA file untouched and emits a warning.

**Exit behavior**

Exits with status `0` on successful removal, status `2` if the FASTA file does not exist, and status `3` (with a warning, not treated as a hard failure by `start.sh`) if no mitochondrial sequence is found.

### `filter_chromosomes.R`

An R script invoked internally by `start.sh` (when `filter` is `all` or `chrom`) to retain only the main chromosomes/scaffolds in the genome FASTA file before indexing.

**Validation checks performed**

1. Confirms the FASTA file exists and that the `quiet` value is `true`/`false`.
2. Validates the supplied `chrom_pattern` regex, if provided, falling back to the default pattern `^(chr)?([0-9]{1,3}|[XYZW]|MT?)$` otherwise.
3. Loads the FASTA file via `Biostrings::readDNAStringSet` and matches sequence identifiers against the pattern.
4. If at least one sequence matches the naming pattern, keeps only the matching sequences.
5. If no sequence matches the naming pattern, falls back to a length-distribution heuristic: sequences are sorted by length and split at the largest consecutive length-ratio gap, retaining the longer (main) sequences and discarding the rest.
6. Overwrites the FASTA file with the retained sequence set and logs which sequences were discarded.

**Exit behavior**

Exits with status `1` on missing FASTA file, invalid regex pattern, invalid `quiet` value, or if the selection logic discards all sequences. Exits with status `0` once chromosome filtering completes successfully.