#!/bin/bash
set -x -e

# Root of the tau atlas
ROOT=/project/hippogang_2/pauly/tau_atlas

# Add to path
PATH=$ROOT/bin:$PATH

# Temp directory
if [[ ! $TMPDIR ]]; then
  if [[ $__LSF_JOB_TMPDIR__ ]]; then
    TMPDIR=$__LSF_JOB_TMPDIR__
  else
    TMPDIR=/tmp/recon_${PPID}
    mkdir -p $TMPDIR
  fi
fi

function pybatch()
{
  mkdir -p $ROOT/dump
  $ROOT/scripts/pybatch.sh -o $ROOT/dump "$@"
}

# This is a function used to "rescue" warp chains from tau_atlas directories. The issue here is that the
# warp chains might be updated after the image has been provided to Sydney for manual segmentation, in which
# case, the segmentation will no longer map into the whole MRI space correctly. This code is run for a given
# specimen and block and extracts a warp chain into a temporary location. Then we should verify that this indeed
# matches what was given to Sydney and then stash it on PennBox along with Sydney's segmentation so that we
# have a mapping from the segmentation to raw MRI space
function rescue_warp_chain()
{
  id=${1?}
  block=${2?}

  # Output directory
  OUTDIR=$ROOT/tmp/rescue_hisseg_warp_chains/${id}/$block/
  mkdir -p $OUTDIR

  # First check the old, Brain paper registrations
  if [[ -d $ROOT/brain_work/${id} ]]; then

    XVIV_BLOCK_TO_HIRES_CHAIN=(
      "$ROOT/brain_work/${id}/mri/${id}_mri_warp_fx_hires_mv_mold.nii.gz"
      "$ROOT/manual/${id}/hires_to_mold/${id}_mri_hires_to_mold_affine.mat,-1"
      "$ROOT/brain_work/${id}/bfreg/${block}/${id}_${block}_bfvis_to_mri_affine_full.mat")

    XVIV_HIRES_TO_BLOCK_CHAIN=(
      "$ROOT/brain_work/${id}/bfreg/${block}/${id}_${block}_bfvis_to_mri_affine_full.mat,-1"
      "$ROOT/manual/${id}/hires_to_mold/${id}_mri_hires_to_mold_affine.mat"
      "$ROOT/brain_work/${id}/mri/${id}_mri_invwarp_fx_hires_mv_mold.nii.gz")

    XVIV_BLOCK_REF_SPACE="$ROOT/brain_work/${id}/bfreg/${block}/${id}_${block}_bfvis_refspace.nii.gz"

  elif [[ -f $ROOT/work/${id}/bfreg/${block}/${id}_${block}_hires_mri_to_bfvis_full_invwarp.nii.gz ]]; then

    XVIV_BLOCK_TO_HIRES_CHAIN=(
      "$ROOT/work/${id}/bfreg/${block}/${id}_${block}_hires_mri_to_bfvis_full_invwarp.nii.gz")

    XVIV_HIRES_TO_BLOCK_CHAIN=(
      "$ROOT/work/${id}/bfreg/${block}/${id}_${block}_hires_mri_to_bfvis_full_warp.nii.gz")

    XVIV_BLOCK_REF_SPACE="$ROOT/work/${id}/bfreg/${block}/${id}_${block}_bfvis_refspace.nii.gz"

  fi

  # Make a copy of the warp chain
  for ((i=0;i<${#XVIV_BLOCK_TO_HIRES_CHAIN[*]};i++)); do
    FN=$(echo ${XVIV_BLOCK_TO_HIRES_CHAIN[i]} | sed -e "s/,.*$//")
    if [[ ! -f $FN ]]; then
      >&2 echo "MISSING FILE: $FN"
      return
    fi
    cp -a $FN $OUTDIR
    echo ${XVIV_BLOCK_TO_HIRES_CHAIN[i]}
  done > $OUTDIR/${id}_${block}_bfvis_to_hires_chain.txt

  # Make a copy of the warp chain
  for ((i=0;i<${#XVIV_HIRES_TO_BLOCK_CHAIN[*]};i++)); do
    FN=$(echo ${XVIV_HIRES_TO_BLOCK_CHAIN[i]} | sed -e "s/,.*$//")
    if [[ ! -f $FN ]]; then
      >&2 echo "MISSING FILE: $FN"
      return
    fi
    cp -a $FN $OUTDIR
    echo ${XVIV_HIRES_TO_BLOCK_CHAIN[i]}
  done > $OUTDIR/${id}_${block}_hires_to_bfvis_chain.txt

  # Transform the hires MRI into the BVFIS space, in order to compare with the
  # image that was given to Sydney for segmentation - this is a kind of sanity
  # check to make sure the warps are correct
  greedy -d 3 \
    -rf $XVIV_BLOCK_REF_SPACE \
    -rm $ROOT/input/${id}/hires_mri/${id}_mri_hires.nii.gz $OUTDIR/${id}_${block}_hires_mri_warped_to_bfvis.nii.gz \
    -r ${XVIV_HIRES_TO_BLOCK_CHAIN[*]}

}


# Main entrypoint into script
COMMAND=$1
shift
$COMMAND "$@"
