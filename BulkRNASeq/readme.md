# Bulk RNA-Seq Pipeline

## Overview

The bulk_rnaseq pipeline performs quality control, read alignment against a reference genome, and gene expression quantification for bulk cellular populations to generate expression count matrices suitable for differential expression analysis and principal component analysis (PCA).

---

## Sample Sheet Generator (generate_samplemetadata.py)

### Description

generate_samplemetadata.py is a Python utility designed to scan a raw sequence data directory recursively, parse sample filenames, and generate a standardized metadata file (sampleMetaData.csv). 

The script automatically detects plain or gzipped FASTQ files, extracts sample attributes, groups paired-end or multi-lane reads into consistent sample numbers, handles cross-platform path separators (ensuring POSIX compatibility for Docker/Linux runtime execution), and populates a structured CSV sheet required by downstream alignment and quantification workflows.

### Command-Line Interface & Parameters

Usage:
  python generate_samplemetadata.py <INPUT_DIR> [OUTPUT_PATH]

Arguments:
  INPUT_DIR      Base directory containing FASTQ files (Required)
  OUTPUT_PATH    Optional target folder or target CSV file path (Default: ./sampleMetaData.csv)

Options:
  -h, --help     Show usage help message and exit

#### Parameter Behavior

* INPUT_DIR: Path to the directory where raw FASTQ files reside. The script traverses this path recursively to locate all matching sequence files (.fastq, .fq, .fastq.gz, .fq.gz).
* OUTPUT_PATH (Optional):
  * Directory Path (e.g., ./metadata/): Generates the output file named sampleMetaData.csv inside the specified directory.
  * File Path (e.g., ./config/my_samples.csv): Creates the output file with the explicitly provided filename and path.
  * Omitted: Defaults to creating sampleMetaData.csv in the current working directory.

---

### Output File Structure

The generated CSV file contains the following schema:

SampleName    | Base file name of the FASTQ file (Example: Control1_R1.fastq.gz)
SampleFolder  | Relative subfolder path from INPUT_DIR (POSIX slashes) (Example: batch1/lane1)
sampleNumber  | Numeric ID grouping matching sample pairs/replicates (Example: 1)
Batch         | Experimental batch identifier (Example: NA)
Covariate     | Extracted experimental condition/treatment label (Example: Control)
VisName       | Combined condition and replicate identifier for visualization (Example: Control_1)

---

### Usage Examples

1. Basic Usage (Default Output Location)
Scan the ./raw_fastq directory and generate ./sampleMetaData.csv:

python generate_samplemetadata.py ./raw_fastq

2. Specify Output Directory
Scan ./data and save the resulting sampleMetaData.csv into ./config/:

python generate_samplemetadata.py ./data ./config/

3. Specify Custom Output File Path
Scan the current working directory (.) and save as experiment_metadata.csv in ./metadata/:

python generate_samplemetadata.py . ./metadata/experiment_metadata.csv