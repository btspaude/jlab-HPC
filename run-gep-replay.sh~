#!/bin/bash

# ------------------------------------------------------------------------- #
# This script runs real data replay jobs for GMn/nTPE data. It was created  #
# based on Andrew Puckett's script.                                         #
# ---------                                                                 #
# P. Datta <pdbforce@jlab.org> CREATED 11-09-2022                           #
# ---------                                                                 #
# ** Do not tamper with this sticker! Log any updates to the script above.  #
# ------------------------------------------------------------------------- #

#SBATCH --partition=production
#SBATCH --account=halla
#SBATCH --mem-per-cpu=1500

# List of arguments
runnum=$1
maxevents=$2
firstevent=$3
prefix=$4
firstsegment=$5
maxsegments=$6
datadir=$7
outdirpath=$8
run_on_ifarm=$9
analyzerenv=${10}
sbsofflineenv=${11}
sbsreplayenv=${12}
ANAVER=${13}     # Analyzer version
useJLABENV=${14} # Use 12gev_env instead of modulefiles?
JLABENV=${15}    # /site/12gev_phys/softenv.sh version

# paths to necessary libraries (ONLY User specific part) ---- #
export ANALYZER=$analyzerenv
export SBSOFFLINE=$sbsofflineenv
export SBS_REPLAY=$sbsreplayenv
export DATA_DIR=$datadir
# ----------------------------------------------------------- #

ifarmworkdir=${PWD}
if [[ $run_on_ifarm == 1 ]]; then
    SWIF_JOB_WORK_DIR=$ifarmworkdir
fi
echo 'Work directory = '$SWIF_JOB_WORK_DIR

# Enabling module
MODULES=/etc/profile.d/modules.sh 
if [[ $(type -t module) != function && -r ${MODULES} ]]; then 
    source ${MODULES} 
fi 
# Choosing software environment
if [[ (! -d /group/halla/modulefiles) || ($useJLABENV -eq 1) ]]; then 
    source /site/12gev_phys/softenv.sh $JLABENV
    source $ANALYZER/bin/setup.sh
else 
    module use /group/halla/modulefiles
    module load analyzer/$ANAVER
    module list
fi

# setup analyzer specific environments
export ANALYZER_CONFIGPATH=$SBS_REPLAY/replay
source $SBSOFFLINE/bin/sbsenv.sh

export DB_DIR=$SBS_REPLAY/DB
export OUT_DIR=$SWIF_JOB_WORK_DIR
export LOG_DIR=$SWIF_JOB_WORK_DIR

echo 'OUT_DIR='$OUT_DIR
echo 'LOG_DIR='$LOG_DIR

# handling any existing .rootrc file in the work directory
# mainly necessary while running the jobs on ifarm
if [[ -f .rootrc ]]; then
    mv .rootrc .rootrc_temp
fi
cp $SBS/run_replay_here/.rootrc $SWIF_JOB_WORK_DIR

analyzer -b -q 'replay_gmn.C+('$runnum','$maxevents','$firstevent','\"$prefix\"','$firstsegment','$maxsegments')'

outfilename=$OUT_DIR'/e1209019_*'$runnum'*.root'
#logfilename=$LOG_DIR'/replay_gmn_'$runnum'*.log' 
logfilename=$LOG_DIR'/e1209019_*'$runnum'*.log' 

# move output files
mv $outfilename $outdirpath/rootfiles
mv $logfilename $outdirpath/logs

# clean up the work directory
rm .rootrc
if [[ -f .rootrc_temp ]]; then
    mv .rootrc_temp .rootrc
fi
