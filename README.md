# A-simple-batch-annotation-process

# Introduction

This is a simple auxiliary tool for batch annotation of genomes, which relies on the eggNOG database.

# Instructiions

## Install dependencies
Install and configure eggnog-mapper. 
    
    conda install -c bioconda -c conda-forge eggnog-mapper
    
Download and unzip the database.

    wget -c http://eggnog5.embl.de/download/emapperdb-5.0.2/eggnog.db.gz
    wget -c http://eggnog5.embl.de/download/emapperdb-5.0.2/eggnog.taxa.tar.gz
    wget -c http://eggnog5.embl.de/download/emapperdb-5.0.2/eggnog_proteins.dmnd.gz
    wget -c http://eggnog5.embl.de/download/emapperdb-5.0.2/mmseqs.tar.gz
    wget -c http://eggnog5.embl.de/download/emapperdb-5.0.2/pfam.tar.gz
    gunzip eggnog.db.gz eggnog_proteins.dmnd.gz 
    tar -xzvf eggnog.taxa.tar.gz mmseqs.tar.gz pfam.tar.gz

Install parallel

    conda install -c bioconda -c conda-forge eggnog-mapper


