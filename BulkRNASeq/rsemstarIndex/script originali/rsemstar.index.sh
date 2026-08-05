#!/bin/bash
SCRATCH="/data/scratch"
run_file="$SCRATCH/run.info"

echo "rsem-star v0.0.1" >> $run_file

export DATA=$1
echo "prepare rsem-star index v 0.0.1" >> $run_file
echo "Export system variables" >> $run_file
export RSEM="/bin/RSEM-1.3.0"
echo $RSEM >> $run_file
echo "The reference genome folder is " $DATA >> $run_file
echo "The URL for the reference FASTA genome file is:" >> $run_file

URL=$2
wget $URL -O $SCRATCH/genome.fa.gz
gzip -d $SCRATCH/genome.fa.gz
echo "Removing non standard chromosomes and MT"
Rscript /bin/reformat.R
echo "The URL for the GTF genome file is:" >> $run_file
GTF=$3
wget $GTF -O $SCRATCH/genome.gtf.gz
echo "Filtering .gtf"
gzip -dc < $SCRATCH/genome.gtf.gz | awk '{ if ($1 ~ /^[X|Y|0-9]*$/ || $1 ~ /^#/) print $0}' > $SCRATCH/genome.gtf 
#gzip -d $SCRATCH/genome.gtf.gz
THREADS=$4
echo "The n. of used threads are " $THREADS >> $run_file

echo "running rsem-star index" >> $run_file
$RSEM/rsem-prepare-reference -p $THREADS --star --star-path /bin/STAR_2.5 --gtf $SCRATCH/genome.gtf $SCRATCH/genome.fa $SCRATCH/genome
echo "indexing ended" > $run_file

echo "chmod 777 $SCRATCH/*"
chmod 777 $SCRATCH/*
