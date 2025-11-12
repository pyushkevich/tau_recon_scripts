#!/bin/bash

# Read local configuration
MDIR=
if [[ $ROOT ]]; then
  # shellcheck source=scripts/common.sh
  . "$ROOT/scripts/common.sh"
else
  # shellcheck source=scripts/common.sh
  . "$(dirname $0)/common.sh"
fi

function import_blockface_from_box()
{
  REGEXP=$1

  grep "$REGEXP" "$MDIR/blockface_src.txt" | while read -r ID BLOCKS; do

    # Create the corresponding temp directory
    TDIR=$ROOT/tmp/blockface_import/$ID/
    mkdir -p "$TDIR"

    # Rsync the files from Box using boxsync.py
    python3 "$ROOT/scripts/boxsync.py" sync_bf -b 50707921044 -i $ID -l $TDIR

  done
}

function export_blockface_to_gcs()
{
  REGEXP=$1

  grep "$REGEXP" "$MDIR/blockface_src.txt" | while read -r ID BLOCKS; do

    # Create the corresponding temp directory
    TDIR=$ROOT/tmp/blockface_import/$ID/
    mkdir -p "$TDIR"

    # Use gsutil to copy files to GCS bucket
    gsutil -m cp -n "$TDIR/bf_raw/*.jpg" "gs://mtl_histology/${ID}/bf_raw/"
    gsutil -m cp -n "$TDIR/manifest/bf_manifest_${ID}.txt" "gs://mtl_histology/${ID}/manifest/"

  done
}

# Copy blockface images from GCS to local storage
function copy_blockface()
{
  REGEXP=$1

  grep "$REGEXP" "$MDIR/blockface_src.txt" | while read -r ID BLOCKS; do
    for BLOCK in $BLOCKS; do

      # Create the corresponding input directory
      IDIR=$ROOT/input/$ID/blockface/$BLOCK
      mkdir -p "$IDIR"

      # Rsync the files
      gsutil -m cp -n "gs://mtl_histology/${ID}/bf_raw/${ID}_${BLOCK}_??_??.jpg" "$IDIR/"

    done
  done
}

# Organize the MRIs
function copy_mold_mri()
{
  REGEXP=$1

  while read -r ID SDIR args; do

    # Create the input directory
    if [[ $ID =~ $REGEXP ]]; then
      IDIR=$ROOT/input/$ID/mold_mri
      mkdir -p $IDIR

      # If the mold source is "box", copy from PennBox using python script
      if [[ $SDIR == box* ]]; then
        python3 "$ROOT/scripts/boxsync.py" sync_mold -b 63599699899 -i $ID -l $IDIR
      else
        # Copy needed files
        for fn in mtl7t.nii.gz contour_image.nii.gz slitmold.nii.gz holderrotation.mat; do
          rsync -av ${MOLD_SRC_DIR?}/$ID/$SDIR/$fn $IDIR/
        done
      fi
    fi

  done < $MDIR/moldmri_src.txt
}

# Organize the high-resolution MRIs - from FlyWheel
function copy_hires_mri()
{
  REGEXP=$1

  while IFS=$',' read -r ID FWPATH args; do

    if [[ $ID =~ $REGEXP ]]; then
      # Create the input directory
      IDIR=$ROOT/input/$ID/hires_mri
      mkdir -p $IDIR

      # Go there
      pushd $IDIR > /dev/null

      # Base filename
      local FN=$(basename "$FWPATH")

      # Check for existing file
      if [[ -f $FN || -f ${FN}.gz ]]; then
        echo Skipping $ID:$FN
        continue
      fi

      # Copy needed files
      fw download -o $FN "$FWPATH"

      # Compress if needed
      if [[ $FN =~ nii$ ]]; then
        gzip $FN
        ln -sf ${FN}.gz ${ID}_mri_hires.nii.gz
      else
        ln -sf $FN ${ID}_mri_hires.nii.gz
      fi

      popd > /dev/null
    fi

  done < $MDIR/hiresmri_src.csv

}

# Set up projects for manual registration - makes life easier
function setup_manual_mri_regs()
{
  REGEXP=$1
  while read -r ID args; do
    if [[ $ID =~ $REGEXP ]]; then

      # Set up the directories
      MOLDDIR=$ROOT/input/$ID/mold_mri
      HIRESDIR=$ROOT/input/$ID/hires_mri
      MANDIR=$ROOT/manual/$ID/hires_to_mold
      mkdir -p $MANDIR

      # Create the workspace with mold as main, hires as overlay
      itksnap-wt \
        -lsm $MOLDDIR/mtl7t.nii.gz -psn "MOLD MRI" \
        -laa $HIRESDIR/${ID}_mri_hires.nii.gz -psn "HIRES MRI" \
        -o $MANDIR/${ID}_hires_to_mold.itksnap
    fi
  done < $MDIR/moldmri_src.txt
}

function usage()
{
  echo "copy_input.sh : Histology to MRI reconstruction script for R01-AG056014"
  echo "Usage:"
  echo "  copy_input.sh [options] <function> [args]"
  echo "Options:"
  echo "  -d            : Turn on command echoing (for debugging)"
  echo "Primary functions:"
  echo "  import_blockface_from_box <regex> : Copy blockface images from Box to a temp folder"
  echo "  export_blockface_to_gcs <regex>   : Export blockface images from temp folder to GCS"
  echo "  copy_blockface <regex>            : Copy blockface images from Box"
  echo "  copy_mold_mri <regex>             : Copy mold MRIs from Box or local storage"
  echo "  copy_hires_mri <regex>            : Copy high-res MRIs from FlyWheel"
  echo "  setup_manual_mri_regs <regex>     : Set up manual registration projects"
}

# Read the command-line options
while getopts "dhBs:" opt; do
  case $opt in
    d) set -x;;
    h) usage; exit 0;;
    \?) echo "Unknown option $OPTARG"; exit 2;;
    :) echo "Option $OPTARG requires an argument"; exit 2;;
  esac
done

# Get remaining args
shift $((OPTIND - 1))

# No parameters? Show usage
if [[ "$#" -lt 1 ]]; then
  usage
  exit 255
fi

# Main entrypoint into script
COMMAND=$1
if [[ ! $COMMAND ]]; then
  main
else
  # Stupid bug fix for chead
  # if echo $COMMAND | grep '_all' > /dev/null; then
  #  echo "RESET LD_LIBRARY_PATH"
  #  export LD_LIBRARY_PATH=
  #fi
  shift
  $COMMAND "$@"
fi
