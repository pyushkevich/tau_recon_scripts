#!/bin/bash
#$ -S /bin/bash
set -x -e

# This script will download and downsample the SVS files from the
# histology drive.
SERVERS=( \
  10.150.13.41 \
  10.150.13.41 \
  10.150.13.41 )

# Create a list of remote folders
REMOTE_FOLDERS=( \
  "/volume1/Histology/2018_UCLM/INDD107677_UP1" \
  "/volume1/Histology/2018_UCLM/INDD106312_UP4 (PC18-679)" \
  "/volume1/Histology/2018_UCLM/HNL-11-15-L/HNL-11-15-L" )

# Current slide list
ROOT=/data/picsl/pauly/tau_atlas
SLIDE_LIST_FILE=$ROOT/input/histology/slide_src.txt

# Tempdir
if [[ ! $TMPDIR ]]; then
  TMPDIR=/tmp/histology_$PPID
  mkdir -p $TMPDIR
fi

# SED commands to protect paths
SED_PROT_CMD="-e \"s/ /\\\ /g\" -e \"s/(/\\\(/g\" -e \"s/)/\\\)/g\""

# Code for a single file
function process_slide()
{
  LINE_NO=${1?}

  SLIDE_URL=$(cat $SLIDE_LIST_FILE | head -n $LINE_NO | tail -n 1)
  SLIDE_ID=$(basename "$SLIDE_URL" .svs)
  WORK=$ROOT/input/histology/slides/$SLIDE_ID

  # Full size SVS file
  SVS=$TMPDIR/$SLIDE_ID.svs

  # Main output
  MRILIKE=$WORK/${SLIDE_ID}_mrilike.nii.gz
  SUMMARY=$WORK/${SLIDE_ID}_thumbnail.tiff

  # Quit if result exists
  if [[ -f $MRILIKE && -f $SUMMARY ]]; then
    return
  fi

  # Create a work directory
  mkdir -p $WORK

  # Copy the slide into the local directory
  # if [[ ! -f $SVS ]]; then
  scp "$SLIDE_URL" $SVS
  # fi

  # Process the slide
  conda activate base
  if [[ ! -f $MRILIKE ]]; then
    $ROOT/scripts/process_raw_slide.py -i $SVS -o $WORK/${SLIDE_ID}_mrilike.nii.gz -t 100
  fi

  if [[ ! -f $SUMMARY ]]; then
    $ROOT/scripts/process_raw_slide.py -i $SVS -s $WORK/${SLIDE_ID}
  fi

  rn -rm $SVS
}

# Generate a slide list
function gen_slide_list()
{
  mkdir -p $ROOT/input/histology
  for ((i=0;i<${#SERVERS[*]};i++)); do
  
    FOLDER=$(echo ${REMOTE_FOLDERS[i]} | sed -e "s/ /\\\\ /g" -e "s/(/\\\\(/g" -e "s/)/\\\\)/g")
    ssh ${SERVERS[i]} ls $FOLDER/*.svs | sed -e "s/ /\\\\ /g" -e "s/(/\\\\(/g" -e "s/)/\\\\)/g" \
      -e "s/^/${SERVERS[i]}:/"

  done > $SLIDE_LIST_FILE
}

# main loop
function main()
{
  # Generate a list of slides to process
  gen_slide_list

  N=$(cat $SLIDE_LIST_FILE | wc -l)
  
  for ((i=1;i<=$N;i++)); do
    qsub -j y -cwd -V -o $ROOT/dump -N "aperio_$i" \
      $0 process_slide $i

    sleep 180
  done
}

function main_no_qsub()
{
  echo ssh $SERVER ls $REMOTE_FOLDER/*.svs
  SLIDE_LIST=$(ssh $SERVER ls $REMOTE_FOLDER/*.svs)
  for fn in $SLIDE_LIST; do
    bash $0 process_slide $fn
  done
}

# Entrypoint
cmd=${1?}
shift 1
$cmd "$@"
