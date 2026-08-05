library(Biostrings)
genome <- readDNAStringSet("/data/scratch/genome.fa", format="fasta")
genome.bis <- genome[which(nchar(names(genome))< 60),]
genome.bis <- genome.bis[setdiff(seq(1:length(names(genome.bis))),grep("^MT",names(genome.bis)))]
writeXStringSet(genome.bis, "/data/scratch/genome.fa", format="fasta")

