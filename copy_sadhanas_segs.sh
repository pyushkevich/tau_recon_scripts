#!/bin/bash
ROOT=/project/hippogang_2/pauly/tau_atlas

# This should be used in the future when Sadhana moves to PMACS
SRC=/project/hippogang_3/sravikumar/atlasPHG2019/
# SRC=/project/hippogang_2/pauly/tau_atlas/sadhana_phg_chead_copy

# Set this to -nav if you don't want to clobber existing files, -av if you do
CP_OPTS="-nav"

for fn in $(cat $ROOT/manifest/hiresmri_src.csv | awk -F, '{print $1}'); do

  # Sadhana does not use dash for HNL
  fnsrc=${fn/-/_}
  fnsrc=${fnsrc/-/_}
  fnsrc=${fnsrc/HNL_/HNL}

  ML=$(find $SRC/preproc -name "${fnsrc}*_axisalign_phgsegshape_multilabel.nii.gz")
  MAT=$(find $SRC/preproc -name "${fnsrc}*_transform_to_axisalign.mat")
  SRLM=$(find $SRC/inputs -name "${fnsrc}*_axisalign_srlm_sr.nii.gz")

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

    if [[ ! -f $ML ]]; then echo "Missing: ${fnsrc}*_axisalign_phgsegshape_multilabel.nii.gz"; fi
    if [[ ! -f $MAT ]]; then echo "Missing: ${fnsrc}*_transform_to_axisalign.mat"; fi

  fi

done
