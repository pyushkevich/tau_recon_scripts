#!/bin/bash

function usage()
{
  echo "pybatch : Paul's SGE/SLURM launcher"
}

# Check if using SLURM
if sbatch --version 1> /dev/null 2> /dev/null ; then
  MODE="SLURM";
else
  MODE="SGE"
fi

# Read the command-line options
while getopts "m:N:w:o:n:dh" opt; do
  case $opt in

    m) MEMORY=$OPTARG;;
    N) JOBNAME=$OPTARG;;
    w) WAITPATTERN=$OPTARG;;
    o) DUMPDIR=$OPTARG;;
    n) CPUCOUNT=$OPTARG;;
    d) set -x -e;;
    h) usage; exit 0;;
    \?) echo "Unknown option $OPTARG"; exit 2;;
    :) echo "Option $OPTARG requires an argument"; exit 2;;
  esac
done

# Get remaining args
shift $((OPTIND - 1))

# Construct the command line
if [[ $MODE == "SLURM" ]]; then

  # Make temp dir
  TDIR=/tmp/pybatch.$PPID
  mkdir -p $TDIR/jobs $TDIR/stdout

  if [[ $WAITPATTERN ]]; then
    # Get list of matching jobs
    JOBS=$(echo $(cat $TDIR/jobs/${WAITPATTERN} 2> /dev/null ) | sed -e "s/ /,/g")
    if [[ $JOBS != "" ]]; then
      DEPCMD="-d afterany:${JOBS}"
    fi
    srun $DEPCMD /bin/sleep 1
  else

    if [[ $MEMORY ]]; then
      MEMCMD="--mem ${MEMORY}"
    fi

    if [[ $CPUCOUNT ]]; then
      CPUCMD="-n ${CPUCOUNT}"
    fi

    mkdir -p ${DUMPDIR?}
    sbatch \
      -D . --export=ALL $MEMCMD $CPUCMD \
      -o "${DUMPDIR?}/${JOBNAME?}.o%j" \
      -J ${JOBNAME?} $DEPCMD "$@" \
      ${PYBATCH_SLURM_OPTS} | tee $TDIR/stdout/${JOBNAME}

    # Link job to name
    if [[ $? -eq 0 ]]; then
      JID=$(cat $TDIR/stdout/${JOBNAME} | awk '{print $4}')
      echo $JID > $TDIR/jobs/${JOBNAME}
    else
      exit $?
    fi
  fi

elif [[ $MODE == "SGE" ]]; then

  if [[ $WAITPATTERN ]]; then
    qsub -b y -sync y -hold_jid ${WAITPATTERN} -o /dev/null -j y /bin/sleep 1
  else
    if [[ $MEMORY ]]; then
      MEMCMD="-l h_vmem=$MEMORY -l s_vmem=$MEMORY"
    fi
    qsub ${PYBATCH_SGE_OPTS} \
      -cwd -V -j y -o ${DUMPDIR?} -N ${JOBNAME?} $MEMCMD "$@"
  fi

fi
