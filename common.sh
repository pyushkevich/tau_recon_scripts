#!/bin/bash

# Read local configuration (ROOT)
if [[ $TAU_ATLAS_ROOT ]]; then
  . $TAU_ATLAS_ROOT/scripts/env.sh
else
  . "$(dirname $0)/env.sh"
fi

# The script directory where script files are located
SDIR=${ROOT?}/scripts

# The directory with manifest files
MDIR=${ROOT?}/manifest

# PATH
PATH=$ROOT/bin:$PATH

# Main directories
mkdir -p $ROOT/dump

# Make sure there is a tmpdir
if [[ ! $TMPDIR ]]; then
  TMPDIR=/tmp/recon_${PPID}
  mkdir -p $TMPDIR
fi

# Limit threads per CPU
if [[ $SLURM_NPROCS ]]; then
  NSLOTS=$SLURM_NPROCS
elif [[ $LSB_DJOB_NUMPROC ]]; then
  NSLOTS=$LSB_DJOB_NUMPROC
fi
ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$NSLOTS
export NSLOTS ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS

# Clear the SSH CURL host if we are it
if [[ $(hostname) == $CURL_SSH_HOST ]]; then
    unset CURL_SSH_HOST
fi

