#!/bin/bash
OLDIDS=$(cat manifest/bids_anon.txt | awk '{print $1}')
for id in $OLDIDS; do

  mkdir -p manual/$id/bfdc_to_mold
  itksnap-wt -i manual/$id/bf_to_mold/${id}_mri_bf_to_mold_result.itksnap -lpt Viewport -pgt \
    | grep '3> ' | sed -e "s/3> \(.*\)/\1/" > manual/$id/bfdc_to_mold/old_vp.mat

  for BL in $(grep $id manifest/blockface_src.txt | awk '{print $2,$3,$4,$5,$6}'); do

    # Extract old matrix
    itksnap-wt -i manual/$id/bf_to_mold/${id}_mri_bf_to_mold_result.itksnap -lpt $BL -pgt \
      | grep '3> ' | sed -e "s/3> \(.*\)/\1/" \
      > /tmp/bf_${id}_${BL}.mat

    # Figure out the x translation
    c3d brain_work/${id}/blockface/${BL}/${id}_${BL}_blockface.nii.gz -probe 50% \
      | awk '{printf "-1 0 0 %f\n0 -1 0 %f\n0 0 1 0\n0 0 0 1\n",1 * $5,1 * $6}' \
      > /tmp/xy_${id}_${BL}.mat

    # Compose the transformations and save
    c3d_affine_tool /tmp/xy_${id}_${BL}.mat /tmp/bf_${id}_${BL}.mat -mult -o \
      manual/$id/bfdc_to_mold/old_${BL}.mat
  done
done
