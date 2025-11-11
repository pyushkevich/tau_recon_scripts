#!/bin/bash
set -x -e

# Read local configuration
MDIR=
if [[ $ROOT ]]; then
  # shellcheck source=scripts/common.sh
  . "$ROOT/scripts/common.sh"
else
  # shellcheck source=scripts/common.sh
  . "$(dirname $0)/common.sh"
fi

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

      # Copy needed files
      for fn in mtl7t.nii.gz contour_image.nii.gz slitmold.nii.gz holderrotation.mat; do
        rsync -av ${MOLD_SRC_DIR?}/$ID/$SDIR/$fn $IDIR/
      done
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

# Main entrypoint
# Do we need raw blockface anymore?
# copy_blockface "$@"
copy_mold_mri "$@"
copy_hires_mri "$@"
setup_manual_mri_regs "$@"
