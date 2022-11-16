#!/bin/bash

##************************  Description of this script  ****************************##
## This script is used to analyze ChIP-Seq data generated by Illumina 
## machine in single-end mode. (will work on paired-end reads after minor changes) 
##
## This script use single-end <fastq.gz file>, <sample_name>, <species> as input 
## and produces uni-mapped bam file.
##
## This script merge 4 parts together
## (1) Use FastQC to check fastq data quality;
## (2) Use Trimmomatic to trim out low quality bases from fastq.
## (3) Use Bowtie2 to align trimmed fastq files to referrence genome.

## While the 4 parts are merged together, the global variables for top_level_folder 
## and sample_folders will be re-defined in each part. This re-definition
## is not necessary for the execution of this merged script but will make each part
## still a complete script and thus can be copied out for single part running and test.
##*********************************************************************************##

##************ What to do after finish running this script? ***********************##
## After get bam file, MACS2 can be used in combination with a "control" bam file
## (input file for ChIP, or control ChIP-Seq data) to call peaks.
## Then typical downstream operation would be using R and Bioconductor to do 
## personalized analysis specific to the experimental design.
## ChIP seq peaks are usually compared with RNA-Seq data to infer molecular pathways.
##*********************************************************************************##

## ************************* How to use this script?  **************************##
##
## The script should be called in this way:
##
## bash ChIP-Seq_get_unimapped_bam_from_fastq <fastq.gz_file> <sample_name> <species>
## 
## After calling the script a bam file with name <sample_name>_unimapped_sorted.bam
## will be produced
##
## e.g. 
##      bash ChIP-seq_get_unimapped_bam_from_fastq mouse_Nanog.fastq.gz mNanog mouse
##
## Currently, this script only deal with <species> with the name "mouse" or "human"
## which means it is designed for mouse or human samples.
##
## The ChIP-seq data must be illumina single-end reads in fastq.gz format.
##
## Newer sequencing platform is expected while using Trimmomatic to trim reads.
## TruSeq3 adapters are expected which typically means MiSeq or HiSeq Illumina 
## machine is used for sequencing.
##
## The names of samples must be clear and short so that it is easier to distinguish
## different samples. Also the sample_folder names should contain only letters, 
## numbers or underline, should NOT contain space, special characters are not allowed.
##
## Good sample names can be: S1,S2; or Sample1, Sample2; or Ctrl1, Ctrl2; 
## Or Ctrl_S1, Ctrl_S2 ...
##
## A program installation script for all programs needed will also be provided later.
##*********************************************************************************##

## ********** Requirement of software installation ****************************##
## All the programs used in this script must locate in /home/guang/bio_softwares/ folder ##
## All the path of the programs must already write in ~/.bashrc file so that they
## can be called from anywhere(outside the installation folder).
## The programs will be used in this script are:
##     (1) fastqc : read quality access.
##     (2) Trimmomatic : trimming of adapters and low-quality reads filtering
##     (3) Bowtie2 : alignment of reads(fastq.gz file) to referrence genome
##     (4) Samtools : transform .sam file into .bam file
##     (5) sambamba : sort bam file and filter out unmapped and multi-mapped reads
##################################################################################

## ******************* Buliding of genome index for Bowtie2 *********************** ##
##
## This script assumes human and mouse Bowtie2 genome index files are already
## created and stored under /data/guang/genome_index/bowtie2 folder
## for definition of human Bowtie2 genome index:
## human_bowtie2_index=/data/guang/genome_index/bowtie2/human_h38_release97/GRCh38.97
## which is built using human genome downloaded from ENSEMBL 
## (GRCh38 release 97 primary_assembly.fa.gz)
##
## mouse_bowtie2_index=/data/guang/genome_index/bowtie2/mouse_m38_release97/GRCm38.97
## which is built using mouse genome downloaded from ENSEMBL 
## (GRCm38 release 97 primary_assembly.fa.gz)
##
## To build genome index, download the primary_assembly.fa.gz genome file,
## unzip it and put it into /data/guang/genome_index/bowtie2 folder then 
## run the following command(--theads 4 means using 4 threads):
## 
## cd /data/guang/genome_index/bowtie2
## bowtie2-build --thread 4 ./Homo_sapiens.GRCh38.dna.primary_assembly.fa ./human_h38_release97/GRCh38.97
####################################################################################



######### Parameters related to Trimmomatic ##########
# How to run Trimmomatic (inlcude path of Trimmomatic)
execute_Trimmomatic="java -jar /home/guang/bio_softwares/Trimmomatic-0.39/trimmomatic-0.39.jar"
# Paired-end Trimmomatic adapter file
PE_Trimmomatic_adapter="/home/guang/bio_softwares/Trimmomatic-0.39/adapters/TruSeq3-PE.fa"
# Single-end Trimmomatic adapter file
SE_Trimmomatic_adapter="/home/guang/bio_softwares/Trimmomatic-0.39/adapters/TruSeq3-SE.fa"

######################################################

######### Parameters related to Bowtie2 ###############
# Human genome bowtie2 index files
human_bowtie2_index="/data/guang/genome_index/bowtie2/human_h38_release97/GRCh38.97"
# Mouse genome bowtie2 index files
mouse_bowtie2_index="/data/guang/genome_index/bowtie2/mouse_m38_release97/GRCm38.97"
####################################################
##******************* Parameter Definition Finished Here *********************##


##*************** The actual alignment script starts here. ********************##
################################################################################


## ************* Check number of argumnets passed to the script ************** ##
## Here, only number of arguments are checked. This smiplified checking process
## assume the arguments are passed correctly.

# Check if 3 arguments are provided to the script

# Note the stupid spaces for 'if' clause:
# one space after 'if' key word
# one space after '['
# one space before ']'
# one space before '-eq'
# one space after '-eq'
# All the spaces must be provided, for example, if no space before ']'
# '3]' will be considered as one variable not a '3' and a ']'

if ! [ $# -eq 3 ]
	then 
		echo "Please call the script with exactly 3 arguments in the right order"
		echo "The script should be called in this way:"
		echo 'ChIP-Seq_get_unimapped_bam_from_fastq <fastq.gz_file> <sample_name> <species>'
		exit 1
fi

# if clause passed and the script goes on here which means correct argument provided
# then get all the inputs from the user
fastq_file=$1
sample_name=$2
species=$3

# Determine which species is provided so that to determine the right bowtie2 genome inex
if [ $species = "human" ]
	then
		bowtie2_index=$human_bowtie2_index
elif [ $species = "mouse" ]
	then	bowtie2_index=$mouse_bowtie2_index
else
	echo "The script only accept <species> of mouse or human, NO others"
	exit 1
fi


############# Part 1 Check fastq data quality using FastQC ##########################
##********************** Description of Part 1 ****************************##
## In this part, fastqc program will simply be called to produce quality report of 
## the fastq.gz file passed to the script.

echo "fastqc will be used to check read quality. After running fastqc you will get"
echo "$fastq_file\_fastqc.html and $fastq_file\_fastqc.zip"
fastqc $fastq_file


################ Part 2 Trim fastq.gz files using Trimmomatic ###############
##********************** Description of Part 2 ****************************##
## In this part, Trimmomatic will be called to trim out adapters and low quality
## end bases of fastq reads.
##
## This part deal with two possibilities: single-end reads or paired-end reads
## so before doing any real job, the number of fastq files will be checked,
##
## This script expect single-end read, so Trimmomatic will be called using SE mode,
## A file named <sample_name>_Trimmomatic_trimmed.fastq.gz file will be produced
###############################################################################


# Do single-end trimming using Trimmomatic
# java -jar /home/guang/bio_softwares/Trimmomatic-0.39/trimmomatic-0.39.jar SE -phred33 \
$execute_Trimmomatic SE -phred33 \
$fastq_file \
$sample_name\_Trimmomatic_trimmed.fastq.gz \
# ILLUMINACLIP:/home/guang/bio_softwares/Trimmomatic-0.39/adapters/TruSeq3-SE.fa:2:30:10 LEADING:3 \
ILLUMINACLIP:$SE_Trimmomatic_adapter:2:30:10 LEADING:3 \
TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36
#Note: 'ILLUMINACLIP:/home/guang/bio_softwares/Trimmomatic-0.39/adapters/TruSeq3-PE.fa' is used
#      This is default set since newer experiments use TruSeq3 kits.

######################## Quality control and trimming finished ################################


########## Part 3 Align trimmed fastq.gz files to reference genome using Bowtie2 ############

##************************** Description of Part3 ******************************************##
## In this part, the trimmed fastq.gz files will be used as input to Bowtie2 program
## and Bowtie2 will produce aligned .bam file for the fastq.gz file provided.

## If the original data came from single-end Illumina read. There will be only one original
## fastq.gz file and only one trimmed fastq.gz file.
## In this case, Bowtie2 will be called to align this single trimmed fastq.gz file to reference
## genome and will produce one .bam file for downstream analysis. 
################################################################################################

##**************** Software installation and pre-processing  Requirement *********************## 
## (1) Bowtie2 is installed and its installation path is in system $PATH
##    thus can be called anywhere.
## (2) Index of referrence genome is already generated 
##     Use $bowtie2_index to get the right genome index.
## (3) samtools
## (4) sambada
###############################################################################################


# Align the fastq.gz file(no need to unzip) to reference genome index using bowtie2
# explanation of arguments
# -p 6 #6 threads
# -q # input file is fastq file
# --locale # local alignment feature to perform soft-clipping
# -x # path to index files(NOT index file folder), must include the base name of index files
# -U # single end fastq file
# -S # output aligned (.sam) file
bowtie2 -p 6 -q --local \
-x $bowtie2_index \
-U ./$sample_name\_Trimmomatic_trimmed.fastq.gz \
-S ./$sample_name\_trimmed_single_end_aln_unsorted.sam

# Transfer sam into bam using samtools
# Explanation of arguments
# -h: include header in output
# -S: input is in SAM format
# -b: output BAM format
# -o: /path/to/output/file

samtools view -h -S -b \
-o ./$sample_name\_trimmed_single_end_aln_unsorted.bam \
./$sample_name\_trimmed_single_end_aln_unsorted.sam


# Use Sambamba to sort and filter bam file
# https://github.com/biod/sambamba/releases/download/v0.7.0/sambamba-0.7.0-linux-static.gz

# sort the bam file
# Explanation of arguments
# -t: number of threads / cores
# -o: /path/to/output/file
sambamba-0.7.0-linux-static sort -t 6 \
-o ./$sample_name\_trimmed_single_end_aln_sorted.bam \
./$sample_name\_trimmed_single_end_aln_unsorted.bam

# Filtering uniquely mapping reads
# -t: number of threads / cores
# -h: print SAM header before reads(keep the header in the output bam file)
# -f: format of output file (default is SAM)
# -F: set custom filter - we will be using the filter to remove duplicates, multimappers and unmapped reads.
sambamba-0.7.0-linux-static view -h -t 6 -f bam \
-F "[XS] == null and not unmapped and not duplicate" \
./$sample_name\_trimmed_single_end_aln_sorted.bam > ./$sample_name\_trimmed_single_end_aln_sorted_uni_mapped.bam

