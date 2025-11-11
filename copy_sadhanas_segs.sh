#!/bin/bash
ROOT=/project/hippogang_2/pauly/tau_atlas

# Source locations are now in a manifest file
MANIFEST=$ROOT/manifest/whole_mtl_seg.csv

# SRC=/project/hippogang_2/pauly/tau_atlas/sadhana_phg_chead_copy

# Add/remove the -n flag if you don't want to clobber existing files
CP_OPTS="-pL"

for fn in $(cat $ROOT/manifest/hiresmri_src.csv | awk -F, '{print $1}'); do

  # Find the ML filename
  ML=$(awk -F, -v id=$fn '$1==id {print $2}' < $MANIFEST)
  if [[ ! $ML ]]; then
    echo "Whole MTL segmentation for $fn missing in $MANIFEST"
    continue
  fi

  # Get the dir and prefix of the segmentation filename
  MLDIR=$(dirname $ML)
  MLPREF=$(echo $(basename $ML) | sed -e "s/_axisalign.*//")

  # Get the remaining filenames
  MAT=$MLDIR/${MLPREF}_transform_to_axisalign.mat
  SRLM=$MLDIR/${MLPREF}_axisalign_srlmseg_sr.nii.gz

  #echo $ML
  if [[ -f $ML && -f $MAT ]]; then

    WDIR=$ROOT/manual/$fn/mri_seg/
    DEST_NII=$WDIR/${fn}_axisalign_phgsegshape_multilabel.nii.gz
    DEST_MAT=$WDIR/${fn}_raw_to_axisalign.mat

    mkdir -p $WDIR
    cp $CP_OPTS $ML $DEST_NII
    cp $CP_OPTS $MAT $DEST_MAT

    # Same for SRLM
    if [[ -f $SRLM ]]; then
      DEST_SRLM=$WDIR/${fn}_srlm_seg.nii.gz
      cp $CP_OPTS $SRLM $DEST_SRLM
    fi

  else

    if [[ ! -f $ML ]]; then echo "Missing: $ML"; fi
    if [[ ! -f $SRLM ]]; then echo "Missing: $SRLM"; fi
    if [[ ! -f $MAT ]]; then echo "Missing: $MAT"; fi

  fi

done
