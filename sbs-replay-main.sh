#!/bin/bash

# ------------------------------------------------------------------------- #
# This script submits real data replay jobs for SBS experiments. It takes   #
# several arguments as inputs and can analyzer either a single run or a     #
# list of runs to the ifarm or the swif2 system. It is created based on     #
# Provakar Datta's script                                                   #
# ---------                                                                 #
# Sean Jeffas, sj9ry@virginia.edu CREATED 07-24-2023                        #
# ---------                                                                 #
# ** Do not tamper with this sticker! Log any updates to the script above.  #
# ------------------------------------------------------------------------- #

# Setting necessary environments via setenv.sh
source setenv.sh

# List of arguments
runs=$1       # run number 
prefix=-1     # We will initialize the rest in a second
run_on_ifarm=-1
nevents=-1
maxsegments=-1
segments_per_job=-1
use_sbs_gems=             # 0 = no sbs gems, 1 = use sbs gems
# Workflow name (Not relevant if run_on_ifarm = 1)
workflowname=test_workflow
# Specify a directory on volatile to store replayed ROOT files
outdirpath=


type=0  # 1 = multi run from txt file, 0 = single run

# Checking the environments
if [[ ! -d $SCRIPT_DIR ]]; then
    echo -e '\nERROR!! Please set "SCRIPT_DIR" path properly in setenv.sh script!\n'; exit;
elif [[ (! -d $ANALYZER) && ($useJLABENV -eq 1) ]]; then
    echo -e '\nERROR!! Please set "ANALYZER" path properly in setenv.sh script!\n'; exit;
elif [[ ! -d $SBSOFFLINE ]]; then
    echo -e '\nERROR!! Please set "SBSOFFLINE" path properly in setenv.sh script!\n'; exit;
elif [[ ! -d $SBS_REPLAY ]]; then
    echo -e '\nERROR!! Please set "SBS_REPLAY" path properly in setenv.sh script!\n'; exit;
fi

#Description of how to run if the user puts in a wrong input
if [ "$#" -ne 6 ] && [ "$#" -ne 3 ] && [ "$#" -ne 4 ] && [ "$#" -ne 7 ]; then
    echo -e "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo -e "This script expects 2 options for inputs:\n"
    echo -e "Option 1: sbs-replay-main.sh <runnum> <prefix> <nevents> <maxsegments> <segments_per_job> <run_on_ifarm> <use_sbs_gems (optional)>"
    echo -e "<use_sbs_gems> is optional (off by default)\n"
    echo -e "or\n"
    echo -e "Option 2: sbs-replay-main.sh <runlist> <maxsegments> <segments_per_job> <use_sbs_gems (optional)>"
    echo -e "<use_sbs_gems> is optional (off by default)\n"
    echo -e "For option 2 the runlist text file must have the following form:"
    echo -e "<prefix>"
    echo -e "<output_dir_name>"
    echo -e "<workflow_name>"
    echo -e "runnum1"
    echo -e "runnum2"
    echo -e "runnum3"
    echo -e "."
    echo -e "."
    echo -e "."
    echo -e " "
    exit;
fi

#This reads the input and tells if it is a text file or a integer
#If an integer we assume it's a single run, if text file then a list of runs
re='^[0-9]+$'
if ! [[ $runs =~ $re ]] ; then
    type=1;
fi


# If this is a single run replay then we do that
if [ $type -eq 0 ]; then
    if [ "$#" -ne 6 ] && [ "$#" -ne 7 ]; then
	echo -e "!!!! Error, single run replay needs 6 or 7 arguments !!!!"
	echo -e "sbs-replay-main.sh <runnum> <prefix> <nevents> <maxsegments> <segments_per_job> <run_on_ifarm> <use_sbs_gems (optional)>\n"
	exit
    fi
    #read in variables expected for a single run replay
    prefix=$2
    nevents=$3
    maxsegments=$4 
    segments_per_job=$5 
    run_on_ifarm=$6
    use_sbs_gems=$7

    #if use_sbs_gems has no input assume it is 0 (not used)
    if [ -z "$use_sbs_gems" ]
    then
	use_sbs_gems=0
    fi
    #If this is a GMN run force sbs gems to be off
    if [ $prefix = 'e1209019' ]
    then
	use_sbs_gems=0
    fi

elif [ $type -eq 1 ]; then   #Otherwise do a runlist replay
    if [ "$#" -ne 3 ] && [ "$#" -ne 4 ]; then
	echo -e "!!!! Error, runlist replay needs 3 arguments !!!!"
	echo -e "sbs-replay-main.sh <runlist> <maxsegments> <segments_per_job> <use_sbs_gems (optional)>\n"
	exit
    fi
    nevents=-1
    maxsegments=$2 
    segments_per_job=$3 
    use_sbs_gems=$4
    run_on_ifarm=0

    #if use_sbs_gems has no input assume it is 0 (not used)
    if [ -z "$use_sbs_gems" ]
    then
	use_sbs_gems=0
    fi

    #read the configuration info from the text file
    if [ ! -f "$runs" ]; then
	echo "!!!! Error, $runs does not exist !!!!"
	exit
    fi

    prefix=$(head -n 1 "$runs" | tail -n 1)
    outdirpath=$(head -n 2 "$runs" | tail -n 1)
    workflowname=$(head -n 3 "$runs" | tail -n 1)
fi


#Automatically set the data path pased on the experiment number
#Will need to get updated as more experiments are added
export DATA_PATH=halla/sbs/GEnII/raw 

if [ $prefix = 'e1209019' ]
then
    export DATA_PATH=$GMN_DATA_PATH
fi
if [ $prefix = 'e1209016' ]
then
    export DATA_PATH=$GEN_DATA_PATH
fi
if [ $prefix = 'gep5' ]
then
    export DATA_PATH=$GEP_DATA_PATH
fi

#if use_sbs_gems has no input assume it is 0 (not used)
    if [ -z "$use_sbs_gems" ]
    then
	use_sbs_gems=0
    fi

#Check the workflow and out directory name
if [[ $run_on_ifarm -ne 1 ]]; then
    echo -e ' "workflowname" : '$workflowname''
fi
echo -e ' "outdirpath"   : '$outdirpath' \n------'
while true; do
    read -p "Do they look good? [y/n] " yn
    echo -e ""
    case $yn in
	[Yy]*) 
	    break; ;;
	    [Nn]*) 
	    if [[ $run_on_ifarm -ne 1 ]]; then
		read -p "Enter desired workflowname : " temp1
		workflowname=$temp1
	    fi
	    read -p "Enter desired outdirpath   : " temp2
	    outdirpath=$temp2		
	    break; ;;
    esac
done


# Create the output directory if necessary
if [[ ! -d $outdirpath ]]; then
    { #try
	mkdir $outdirpath
    } || { #catch
	echo -e "\n!!!!!!!! ERROR !!!!!!!!!"
	echo -e $outdirpath "doesn't exist and cannot be created! \n"
	exit;
    }
fi
if [[ ! -d $outdirpath'/rootfiles' ]]; then
    { #try
	mkdir $outdirpath'/rootfiles'
    } || { #catch
	echo -e "\n!!!!!!!! ERROR !!!!!!!!!"
	echo -e $outdirpath'/rootfiles' "doesn't exist and cannot be created! \n"
	exit;
    }
fi
if [[ ! -d $outdirpath'/logs' ]]; then
    { #try
	mkdir $outdirpath'/logs'
    } || { #catch
	echo -e "\n!!!!!!!! ERROR !!!!!!!!!"
	echo -e $outdirpath'/logs' "doesn't exist and cannot be created! \n"
	exit;
    }
fi



# Creating the workflow
if [[ $run_on_ifarm -ne 1 ]]; then
    swif2 create $workflowname
else
    echo -e "\nRunning all jobs on ifarm!\n"
fi

#if a single run then we do a single job
if [ $type -eq 0 ]; then
    $SCRIPT_DIR'/submit-sbs-jobs.sh' $runs $prefix $nevents $maxsegments $segments_per_job $use_sbs_gems $run_on_ifarm $outdirpath $workflowname $SCRIPT_DIR $ANALYZER $SBSOFFLINE $SBS_REPLAY $DATA_PATH $ANAVER $useJLABENV $JLABENV
fi


line_num=1
#if a runlist then we loop over all the runs in the file
if [ $type -eq 1 ]; then
    while read runs;
    do 
	#skip the first few lines which were read earlier to get the configuration
	if (( line_num < 4 ));then
	    line_num=$((line_num + 1))
	    continue
	fi
	$SCRIPT_DIR'/submit-sbs-jobs.sh' $runs $prefix $nevents $maxsegments $segments_per_job $use_sbs_gems $run_on_ifarm $outdirpath $workflowname $SCRIPT_DIR $ANALYZER $SBSOFFLINE $SBS_REPLAY $DATA_PATH $ANAVER $useJLABENV $JLABENV
    done < $runs
fi

if [[ $run_on_ifarm -ne 1 ]]; then
    swif2 run $workflowname
    swif2 status $workflowname
fi
