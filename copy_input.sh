#!/bin/bash
set -x -e
RSYNC_ROOT=10.150.13.41:/volume1/Histology/2018_UCLM
ROOT=/data/picsl/pauly/tau_atlas

# The script directory where script files are located
SDIR=$ROOT/scripts

# The directory with manifest files
MDIR=$ROOT/manifest

# Parse the manifest file
function copy_blockface()
{
  while IFS=$'\t' read -r ID BLOCK REMOTEDIR args; do

    # Create the corresponding input directory
    IDIR=$ROOT/input/$ID/blockface/$BLOCK
    mkdir -p $IDIR

    # Rsync the files
    rsync -av "$RSYNC_ROOT/${REMOTEDIR}/*${BLOCK}_??_??.jpg" $IDIR/

  done < $MDIR/blockface_src.txt
}

# Organize the MRIs
function copy_mold_mri()
{
  while read -r ID SDIR args; do

    # Create the input directory
    IDIR=$ROOT/input/$ID/mold_mri
    mkdir -p $IDIR

    # Copy needed files
    for fn in mtl7t.nii.gz contour_image.nii.gz slitmold.nii.gz holderrotation.mat; do
      rsync -av $SDIR/$fn $IDIR/
    done

  done < $MDIR/moldmri_src.txt
}

# Organize the high-resolution MRIs - from FlyWheel
function copy_hires_mri()
{
  while read -r ID FWPATH args; do 

    # Create the input directory
    IDIR=$ROOT/input/$ID/hires_mri
    mkdir -p $IDIR

    # Go there
    pushd $IDIR > /dev/null

    # Base filename
    local FN=$(basename $FWPATH)

    # Check for existing file
    if [[ -f $FN || -f ${FN}.gz ]]; then
      echo Skipping $ID:$FN
      continue
    fi

    # Copy needed files
    fw download -o $FN $FWPATH

    # Compress if needed
    if [[ $FN =~ nii$ ]]; then
      gzip $FN
      ln -sf ${FN}.gz ${ID}_mri_hires.nii.gz
    else
      ln -sf $FN ${ID}_mri_hires.nii.gz
    fi

    popd > /dev/null

  done < $MDIR/hiresmri_src.txt
}

# Set up projects for manual registration - makes life easier
function setup_manual_mri_regs()
{
  while read -r ID args; do

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

  done < $MDIR/moldmri_src.txt
}

# Main entrypoint
copy_blockface
copy_mold_mri
copy_hires_mri
setup_manual_mri_regs
