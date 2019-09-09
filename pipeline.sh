#!/bin/bash

get_input () {

    # Function to parse arguments
    # Specifying usage message
    usage="Usage: sh pipeline.bash -i <input directory> -o <output directory> -[OPTIONS]
              Bacterial short reads genome assembly software. The options available are:
                        -i : Directory for genome sequences [required]
                        -o : Output directory [required]
                        -f : For fast assembly (uses skesa)
                        -q : Flag to perform quality analysis of assembly using Quast
                        -m : Flag to perform quality analysis of reads using FastQC+MultiQC
                        -k : Kmer range for spades (default=99,105,107,115)
                        -v : Flag to turn on verbose mode
                        -h : Print usage instructions"

  #Specifying deafult Arguments
  f=0
  assembler="spades"
  trimming=1
  quast=0
  multiqc=0
  temp_directory="temp"
  kmer_length="99,105,107,115"
  v=0

  #Getopts block, will take in the arguments as inputs and assign them to variables
  while getopts "i:o:fqmk:vh" option; do
          case $option in
                  i) input_directory=$OPTARG;;
                  o) output_directory=$OPTARG;;
                  f) f=1;;
                  q) quast=1;;
                  m) multiqc=1;;
                  k) kmer_length=$OPTARG;;
                  v) v=1;;
                  h) echo "$usage"
                        exit 0;;
                 \?) echo "Invalid option."
                    "$usage"
                             exit 1;;
          esac
  done

  #Check for presence of required arguments
  if [ ! "$input_directory" ] || [ ! "$output_directory" ]
  then
    echo "ERROR: Required arguments missing!"
    echo "$usage"
    exit 1
  fi

  if [ ! -d $input_directory ]
  then echo "ERROR: Not a valid directory"
  echo "$usage"
  exit 1
  fi

  #Check if output file is already present, give option to rewrite.
	if [ -d $output_directory ]
        then
		echo "Output directory already exists, would you like to overwrite? Reply with y/n"
		read answer
		case $answer in
			y) echo "Overwriting folder $output in subsequent steps";;
			n) echo "Folder overwrite denied, exiting SNP pipeline"
				exit 1;;
			\?) echo "Incorrect option specified, exiting SNP pipeline"
				exit 1;;
		esac
	fi

  #If 'fast' option is selected, turn off trimming and assemble using SKESA
  if [ $f == 1 ]
  then
    assembler="skesa"
    trimming=0
  fi
  
  #Export kmer var to be used within xargs
  export kmer_length


}

prepare_temp(){
  if  [ "$v" == 1 ]
  then
    echo "Preparing temp directory"
  fi

  mkdir -p temp
  mkdir -p $output_directory

  #Export input_directory var to be used within xarg commands
  export input_directory

  #parsing through input directory (ASSUMPTION: paired reads with names according to proper convention) and storing name of genomes and extension in file
  ls $input_directory | xargs -L2 bash -c 'a=${0%_*};ext=${0#*.};echo $a >> temp/genomes_list.txt;echo $ext >>temp/genomes_list.txt'
}

perform_trimming()
{
  if  [ "$v" == 1 ]
  then
	   echo "Trimming with trimmomatic"
  fi
	mkdir -p temp/trim

  #Perform trimming for all files
  cat temp/genomes_list.txt | xargs -L2 bash -c 'trimmomatic PE $input_directory/"$0"_1."$1" $input_directory/"$0"_2."$1" temp/trim/"$0"_1."$1" temp/trim/"$0"_1_UP."$1" temp/trim/"$0"_2."$1" temp/trim/"$0"_2_UP."$1" SLIDINGWINDOW:12:18 MINLEN:100 AVGQUAL:18'

  #Combing both unpaired files into one file
  cat temp/genomes_list.txt | xargs -L2 bash -c 'cat temp/trim/"$0"_1_UP."$1" temp/trim/"$0"_2_UP."$1" > temp/trim/"$0"_UP."$1"; rm temp/trim/"$0"_1_UP."$1" temp/trim/"$0"_2_UP."$1"'

  if  [ "$v" == 1 ]
  then
     echo "Trimming done!"
  fi
}

spades_assembly(){

  if  [ "$v" == 1 ]
  then
    echo "Spades assembly"
  fi

  mkdir -p temp/spades

  cat temp/genomes_list.txt | xargs -L2 bash -c 'spades.py -k $kmer_length -1 temp/trim/"$0"_1."$1" -2 temp/trim/"$0"_2."$1" -s temp/trim/"$0"_UP."$1" --careful --cov-cutoff auto -o temp/spades/"$0"'

  mv temp/spades  $output_directory/
}

quality_analysis(){

	assembler=skesa
	echo “Quast: Quality Assessment Tool for Genome Assemblies”
	mkdir -p temp/quast
	if [ "$assembler" == "spades" ]
	then
	mkdir -p $output_directory/quast/
	for k in $(ls $output_directory/spades/)
	do
        	cp $output_directory/spades/$k/scaffolds.fasta temp/quast/
        	mv temp/quast/scaffolds.fasta temp/quast/$k"_scaffolds.fasta"
	done
	quast.py temp/quast/* -o $output_directory/quast/
	fi

	if [ "$assembler" == "skesa" ]
	then
	mkdir -p $output_directory/quast/
	quast.py $output_directory/skesa/* -o $output_directory/quast/
	fi
	}

quality_control(){
#input directory i
#output is created in the fastqc_output
  echo "quality control function here"
  mkdir -p temp/fastqc_output
  if [ "$trimming" == 1 ];then
    fastqc temp/trim/* -o temp/fastqc_output
    multiqc temp/fastqc_output/*.zip -o temp/multiqc_output
  else
    fastqc $input_directory/* -o temp/fastqc_output
    multiqc temp/fastqc_output/*.zip -o temp/multiqc_output
  fi

  mv temp/multiqc_output $output_directory/
}

skesa_assembly(){
  echo "Skesa: assembly function here"
  mkdir -p temp/skesa
  mkdir "$output_directory"/skesa

  cat temp/genomes_list.txt | xargs -L2 bash -c 'skesa --fastq "$input_directory"/"$0"_1."$1","$input_directory"/"$0"_2."$1" --contigs_out temp/skesa/"$0"_skesa_contigs.fa'

  mv  temp/skesa/* "$output_directory"/skesa/
}

main() {

  get_input "$@"

  if [ "$v" == 1 ]
  then
          echo "Preparing temp_directory..."
  fi

  prepare_temp $input_directory

  if [ "$v" == 1 ]
  then
          echo "Temp directory created"
  fi

  if [ "$trimming" == 1 ]
  then

    if [ "$v" == 1 ]
    then
   	  echo "Performing trimming..."
    fi

  	perform_trimming

  fi


  if [ "$multiqc" == 1 ]
  then
    if [ "$v" == 1 ]
    then
            echo "Quality analysis of reads intiated..."
    fi
    quality_control $input_directory
    if [ "$v" == 1 ]
    then
            echo "Quality analysis of reads completed..."
    fi
  fi

  if [ "$assembler" == "spades" ]
  then
    if [ "$v" == 1 ]
    then
            echo "SPAdes assemblies intiated..."
    fi
    spades_assembly $input_directory $kmer_length
    if [ "$v" == 1 ]
    then
            echo "SPAdes assemblies completed..."
    fi
  fi


  if [ "$assembler" == "skesa" ]
  then
    if [ "$v" == 1 ]
    then
            echo "SKESA assemblies intiated..."
    fi
    skesa_assembly $input_directory
    if [ "$v" == 1 ]
    then
            echo "SKESA assemblies completed..."
    fi
  fi


  if [ "$quast" == 1 ]
  then
    if [ "$v" == 1 ]
    then
            echo "Quality analysis of assemblies initiated.."
    fi
    quality_analysis
    if [ "$v" == 1 ]
    then
            echo "Quality analysis of assemblies completed.."
    fi
	fi

  if [ "$v" == 1 ]
  then
          echo "Assembly pipeline complete!"
  fi

  rm -r temp
}

# Calling the main function
main "$@"

