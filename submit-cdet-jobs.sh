#!/bin/bash

# ------------------------------------------------------------------------- #
# This script submits real data replay jobs for GMn/nTPE data to batch farm.# 
# There is a flag to force all the jobs to run on ifarm instead. It was     #
# created based on Andrew Puckett's script.                                 #
# ---------                                                                 #
# P. Datta <pdbforce@jlab.org> CREATED 11-09-2022                           #
# ---------                                                                 #
# ** Do not tamper with this sticker! Log any updates to the script above.  #
# ------------------------------------------------------------------------- #

# Setting necessary environments via setenv.sh
source setenv.sh
export DATA_DIR=/cache/mss/halla/sbs/GEp/raw

# List of arguments
runnum=$1       # run number 
nevents=$2      # total no. of events to replay
maxsegments=$3  # maximum no. of segments (or jobs) to analyze
run_on_ifarm=$4 # 1=>Yes (If true, runs all jobs on ifarm)
# Workflow name (Not relevant if run_on_ifarm = 1)
workflowname=
# Specify a directory on volatile to store replayed ROOT files
outdirpath=

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

# Validating the number of arguments provided
if [[ "$#" -ne 4 ]]; then
    echo -e "\n--!--\n Illegal number of arguments!!"
    echo -e " This script expects 4 arguments: <runnum> <nevents> <maxsegments> <run_on_ifarm>\n"
    exit;
else 
    echo -e '\n------'
    echo -e ' Check the following variable(s):'
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
fi

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

for ((i=0; i<=$maxsegments; i++))
do
    #fnameout_pattern='/farm_out/pdbforce/pdatta_gmn_'$runnum'_segment'$i'.out'
    #sbatch --output=$fnameout_pattern run_GMN_sbatch_nohodo.sh $runnum -1 0 e1209019 $i 1
    jobname=${USER}'_cdet_'$runnum'_segment'$i
    
    # look for first segment on cache disk:
    firstsegname='gep5_'$runnum'.evio.0.0'
    mssfirst='mss:/mss/halla/sbs/GEp/raw/'$firstsegname
    cachefirst='/cache/mss/halla/sbs/GEp/raw/'$firstsegname
    
    eviofilename='gep5_'$runnum'.evio.0.'$i
    mssfilename='mss:/mss/halla/sbs/GEp/raw/'$eviofilename
    cachefile='/cache/mss/halla/sbs/GEp/raw/'$eviofilename
    
    script=$SCRIPT_DIR'/run-cdet-replay.sh'

    testfilename='/mss/halla/sbs/GEp/raw/'$eviofilename

    #output structures come from replay script
    outfilename='match:cdet_'$runnum'_'$nevents'.root'
    #logfilename='match:gep5_fullreplay_'$runnum'*seg'$i'*.log'

    outcopydir=$outdirpath'/rootfiles'
    logcopydir=$outdirpath'/logs'

    if [ -f "$testfilename" ]; then

	if [[ $run_on_ifarm -ne 1 ]]; then

	    echo 'Adding new swif2 job, runnum='$runnum', segment='$i     
	    if [ $i -gt 0 ]; then
		echo 'segment '$i' also requires first segment'
		swif2 add-job -workflow $workflowname -partition production -name $jobname -cores 1 -disk 25GB -ram 1500MB -input $cachefile $mssfilename -input $cachefirst $mssfirst $script $runnum $nevents 0 gep5 $i 1 $DATA_DIR $outdirpath $run_on_ifarm $ANALYZER $SBSOFFLINE $SBS_REPLAY $ANAVER $useJLABENV $JLABENV
	    else
		echo 'segment '$i' IS first segment'
		swif2 add-job -workflow $workflowname -partition production -name $jobname -cores 1 -disk 25GB -ram 1500MB -input $cachefile $mssfilename $script $runnum $nevents 0 gep5 $i 1 $DATA_DIR $outdirpath $run_on_ifarm $ANALYZER $SBSOFFLINE $SBS_REPLAY $ANAVER $useJLABENV $JLABENV
	    fi
	    
	else
	    if [ -f "$cachefile" ]; then
		$script $runnum $nevents 0 gep5 $i 1 $DATA_DIR $outdirpath $run_on_ifarm $ANALYZER $SBSOFFLINE $SBS_REPLAY $ANAVER $useJLABENV $JLABENV
	    else
		echo -e "!*!ERROR!!" $cachefile "doesn't exist!"
	    fi
	fi
    fi
done

# run the workflow and then print status
if [[ $run_on_ifarm -ne 1 ]]; then
    swif2 run $workflowname
    echo -e "\n Getting workflow status.. [may take a few minutes!] \n"
    swif2 status $workflowname
fi
