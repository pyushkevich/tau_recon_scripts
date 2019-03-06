#!/bin/bash
set -x -e
ROOT=/data/picsl/pauly/tau_atlas
mkdir -p $ROOT/dump

# Set the paths for the tools
export PATH=/data/picsl/pauly/bin:/data/picsl/pauly/bin/ants:$PATH

# The directory with manifest files
MDIR=$ROOT/manifest

# Make sure there is a tmpdir
if [[ ! $TMPDIR ]]; then
  TMPDIR=/tmp/recon_${PPID}
  mkdir -p $TMPDIR
fi

# Common QSUB options
QSUBOPT="-cwd -V -j y -o $ROOT/dump"

# Set common variables for a specimen
function set_specimen_vars()
{
  read -r id args <<< "$@"

  # MRI inputs (7T for the mold)
  MOLD_MRI_INPUT_DIR=$ROOT/input/${id}/mold_mri
  MOLD_MRI=$MOLD_MRI_INPUT_DIR/mtl7t.nii.gz
  MOLD_CONTOUR=$MOLD_MRI_INPUT_DIR/contour_image.nii.gz

  # The slitmold may not be in the orientation we want. This is the raw input
  MOLD_BINARY_NATIVE=$MOLD_MRI_INPUT_DIR/slitmold.nii.gz
  MOLD_RIGID_MAT_NATIVE=$MOLD_MRI_INPUT_DIR/holderrotation.mat

  # MRI inputs (hi-res 9.4T)
  HIRES_MRI_INPUT_DIR=$ROOT/input/${id}/hires_mri
  HIRES_MRI=$HIRES_MRI_INPUT_DIR/${id}_mri_hires.nii.gz

  # Manual registration of mold and affine MRI
  MANUAL_DIR=$ROOT/manual/$id
  HIRES_TO_MOLD_AFFINE=$MANUAL_DIR/hires_to_mold/${id}_mri_hires_to_mold_affine.mat

  # The mask for the high-resolution MRI
  HIRES_MRI_REGMASK=$MANUAL_DIR/hires_to_mold/${id}_mri_hires_mask.nii.gz

  # Registration between low-res and high-res MRI
  MRI_WORK_DIR=$ROOT/work/${id}/mri
  MOLD_BINARY=$MRI_WORK_DIR/slitmold_std.nii.gz
  MOLD_RIGID_MAT=$MRI_WORK_DIR/holderrotation_std.mat
  MOLD_NATIVE_TO_STD_MAT=$MRI_WORK_DIR/mold_native_to_std.mat
  MOLD_MRI_CROP=$MRI_WORK_DIR/${id}_mold_mri_crop.nii.gz
  MOLD_MRI_MASK_NATIVESPC=$MRI_WORK_DIR/${id}_mold_mri_mask_nativespc.nii.gz
  MOLD_MRI_MASK_MOLDSPC=$MRI_WORK_DIR/${id}_mold_mri_mask_moldspc.nii.gz
  MOLD_MRI_N4=$MRI_WORK_DIR/${id}_mold_mri_n4.nii.gz
  MOLD_TO_HIRES_WARP=$MRI_WORK_DIR/${id}_mri_warp_fx_hires_mv_mold.nii.gz
  MOLD_TO_HIRES_ROOT_WARP=$MRI_WORK_DIR/${id}_mri_rootwarp_fx_hires_mv_mold.nii.gz
  MOLD_TO_HIRES_INV_WARP=$MRI_WORK_DIR/${id}_mri_invwarp_fx_hires_mv_mold.nii.gz
  MOLD_TO_HIRES_WORKSPACE=$MRI_WORK_DIR/${id}_mri_warp_fx_hires_mv_mold.itksnap
  RESLICE_MOLD_TO_HIRES=$MRI_WORK_DIR/${id}_mri_mold_reslice_to_hires.nii.gz

  # Workspaces for mold-blockface preregistration
  MOLD_WORKSPACE_DIR=$MANUAL_DIR/bf_to_mold
  MOLD_WORKSPACE_SRC=$MANUAL_DIR/bf_to_mold/${id}_mri_bf_to_mold_input.itksnap
  MOLD_WORKSPACE_RES=$MANUAL_DIR/bf_to_mold/${id}_mri_bf_to_mold_result.itksnap

  # Rotation of the holder around z axis to have the right orientation for viewingw
  MOLD_REORIENT_VIZ=$MRI_WORK_DIR/${id}_mold_viz.mat
}

# Set common variables for a block
function set_block_vars()
{
  read -r id block args <<< "$@"

  # Specimen data
  set_specimen_vars $id

  # Blockface stuff
  BF_INPUT_DIR=$ROOT/input/${id}/blockface/${block}
  BF_RECON_DIR=$ROOT/work/$id/blockface/$block
  BF_RECON_NII=$BF_RECON_DIR/${id}_${block}_blockface.nii.gz

  # Slide selection for the block
  BF_SLIDES=$BF_RECON_DIR/${id}_${block}_slides.txt

  # Blockface registration stuff
  BF_REG_DIR=$ROOT/work/$id/bfreg/$block

  # Manually generated transform taking block to mold space
  BF_TOMOLD_MANUAL_RIGID=$BF_REG_DIR/${id}_${block}_blockface_tomold_manual_rigid.mat

  # MRI-like image extracted from blockface
  BF_MRILIKE=$BF_REG_DIR/${id}_${block}_blockface_mrilike.nii.gz

  # MRI crudely mapped to block space
  MRI_TO_BF_INIT=$BF_REG_DIR/${id}_${block}_mri_toblock_init.nii.gz
  MRI_TO_BF_INIT_MASK=$BF_REG_DIR/${id}_${block}_mri_toblock_init_mask.nii.gz

  # Matrix to initialize rigid
  BF_TO_MRI_RIGID=$BF_REG_DIR/${id}_${block}_rigid_invgreen.mat
  BF_TO_MRI_AFFINE=$BF_REG_DIR/${id}_${block}_affine_invgreen.mat
  BF_TO_MRI_WORKSPACE=$BF_REG_DIR/${id}_${block}_bf_to_mri_affinereg.itksnap

  # Affine resliced MRI matched to the blockface
  MRI_TO_BF_AFFINE=$BF_REG_DIR/${id}_${block}_mri_toblock_affine.nii.gz
  MRI_TO_BF_AFFINE_MASK=$BF_REG_DIR/${id}_${block}_mri_toblock_affine_mask.nii.gz

  # Hires MRI resampled to block
  HIRES_MRI_TO_BF_AFFINE=$BF_REG_DIR/${id}_${block}_hires_mri_toblock_affine.nii.gz
  HIRES_MRI_TO_BF_WARPED=$BF_REG_DIR/${id}_${block}_hires_mri_toblock_warped.nii.gz
  HIRES_MRI_MASK_TO_BF_WARPED=$BF_REG_DIR/${id}_${block}_hires_mri_mask_toblock_warped.nii.gz

  # Rotation matrix to make the block properly oriented for human viewing
  BF_REORIENT_VIZ=$BF_REG_DIR/${id}_${block}_blockface_reorient_2d.mat

  # Intensity remapped histology block
  BF_REORIENTED=$BF_REG_DIR/${id}_${block}_blockface_tomold_reoriented.nii.gz
  BF_MRILIKE_REORIENTED=$BF_REG_DIR/${id}_${block}_blockface_tomold_invgreen_reoriented.nii.gz

  # Sequence of transforms to take MOLD MRI to native space
  MRI_TO_BF_AFFINE_FULL="$BF_TO_MRI_AFFINE,-1 $BF_TOMOLD_MANUAL_RIGID,-1 $MOLD_RIGID_MAT"
  HIRES_TO_BF_AFFINE_FULL="$MRI_TO_BF_AFFINE_FULL $HIRES_TO_MOLD_AFFINE"
  HIRES_TO_BF_WARP_FULL="$HIRES_TO_BF_AFFINE_FULL $MOLD_TO_HIRES_INV_WARP"

  # Workspace of MRI in BF space
  MRI_TO_BF_WORKSPACE=$BF_REG_DIR/${id}_${block}_mri_to_bf.itksnap

}

# This function reconstructs the blockface images
# TODO: this does not correct for shifts between the blockface images. It would be 
# better to perform some kind of groupwise alignment of the blockface images first
# but this should be handled by a separate C++ program, not bash
function recon_blockface()
{
  # Read all the arguments
  read -r id block spacing offset size resample first last swapdim args <<< "$@"

  # Get the variables
  set_block_vars $id $block

  # Create it
  mkdir -p $BF_RECON_DIR

  # Generate a list of slides that are in prescribed range
  ls $BF_INPUT_DIR | grep 'jpg$' | \
    awk -v first=$first -v last=$last \
      '(NR >= first) && (NR <= last || last < 0) {print $0}' \
    > $BF_SLIDES

  # Trim the block and split the color channels
  for fn in $(cat $BF_SLIDES); do

    # Crop region, scale by needed factor, split into RGB
    RGBDIR=$TMPDIR/$id/$block
    mkdir -p $RGBDIR

    # Resampling commands
    if [[ $resample -eq 1 ]]; then
      RESCOM=""
    else
      RESCOM=$(echo $resample | awk '{printf "-smooth-fast %gvox -resample %g%%\n",$1/2.0,100/$1}')
    fi

    # Crop and resample
    c2d -mcs -verbose $BF_INPUT_DIR/$fn \
      -foreach -region $offset $size $RESCOM -endfor \
      -type uchar -omc $TMPDIR/temp_${fn/.jpg/.png}

    # Swap dimensions (rotate & flip)
    c3d -verbose -mcs $TMPDIR/temp_${fn/.jpg/.png} \
      -foreach -swapdim ${swapdim} -orient RAI -endfor \
      -type uchar -oo $RGBDIR/rgb%02d_${fn/.jpg/.png}

  done

  # Flip?
  FLIP=$(echo $block | cut -c 4-4 | sed -e "s/a//" -e "s/p/-flip z/")

  c3d \
    -verbose \
    $RGBDIR/rgb00*.png -tile z -popas R \
    $RGBDIR/rgb01*.png -tile z -popas G \
    $RGBDIR/rgb02*.png -tile z -popas B \
    -push R -push G -push B \
    -foreach -spacing $spacing $FLIP -endfor \
    -omc $BF_RECON_NII
}

function recon_blockface_all()
{
  # Read an optional regular expression from command line
  REGEXP=$1

  # Process the individual blocks
  cat $MDIR/blockface_param.txt | grep "$REGEXP" | while read -r id block args; do

    # Submit the jobs
    qsub $QSUBOPT -N "recon_bf_${id}_${block}" \
      -l h_vmem=16G -l s_vmem=16G \
      $0 recon_blockface $id $block $args

  done

  # Wait for completion
  qsub $QSUBOPT -b y -sync y -hold_jid "recon_bf_*" /bin/sleep 0
}

# Perform registration between two MRI scans, preprocessing for block registration
function process_mri()
{
  # Read all the arguments
  read -r id mold_orient args <<< "$@"

  # Get the variables
  set_specimen_vars $id

  # Make directories
  mkdir -p $MRI_WORK_DIR

  # Stanardize the orientation of the molds
  c3d $MOLD_BINARY_NATIVE -orient $mold_orient -o $MOLD_BINARY
  c3d_affine_tool -sform $MOLD_BINARY -sform $MOLD_BINARY_NATIVE -inv -mult -inv \
    -o $MOLD_NATIVE_TO_STD_MAT
    
  c3d_affine_tool $MOLD_RIGID_MAT_NATIVE $MOLD_NATIVE_TO_STD_MAT -mult -o $MOLD_RIGID_MAT 

  # Crop the MRI to the region used to make the mold
  c3d $MOLD_CONTOUR $MOLD_MRI -reslice-identity -o $MOLD_MRI_CROP

  # Perform N4 normalization of the MRI
  c3d $MOLD_CONTOUR -thresh -inf 0 1 0 -type uchar -o $MOLD_MRI_MASK_NATIVESPC
  N4BiasFieldCorrection -d 3 -i $MOLD_MRI_CROP -o $MOLD_MRI_N4 -x $MOLD_MRI_MASK_NATIVESPC

  # Generate a mask of the mold MRI in mold space
  c3d $MOLD_BINARY $MOLD_CONTOUR -shift -1 -reslice-matrix $MOLD_RIGID_MAT \
    -thresh -inf -1 1 0 -o $MOLD_MRI_MASK_MOLDSPC

  # Registration with high-resolution image as fixed, low-resolution as moving, lots of smoothness
  greedy -d 3 -i $HIRES_MRI $MOLD_MRI_N4 -it $HIRES_TO_MOLD_AFFINE,-1 \
    -o $MOLD_TO_HIRES_WARP -oroot $MOLD_TO_HIRES_ROOT_WARP \
    -sv -s 3mm 0.2mm -m NCC 8x8x8 -n 40x40x0 -gm $HIRES_MRI_REGMASK \
    -wp 0.0001 -exp 6 

  # Apply the registration
  greedy -d 3 -rf $HIRES_MRI -rm $MOLD_MRI_N4 $RESLICE_MOLD_TO_HIRES \
    -r $MOLD_TO_HIRES_ROOT_WARP,64 $HIRES_TO_MOLD_AFFINE,-1 

  # Generate the inverse warp
  greedy -d 3 -rf $HIRES_MRI -rc $MOLD_TO_HIRES_INV_WARP -wp 0.0001 -r $MOLD_TO_HIRES_ROOT_WARP,-64

  # Create a workspace to encapsulate result
  itksnap-wt \
    -lsm $HIRES_MRI -psn "HIRES_MRI" -props-set-contrast AUTO \
    -laa $RESLICE_MOLD_TO_HIRES -psn "MOLD_MRI_warped" -props-set-contrast AUTO \
    -laa $MOLD_TO_HIRES_WARP -psn "Warp" \
    -o $MOLD_TO_HIRES_WORKSPACE

  # Also create a workspace for the mold - to help match up blockface slices
  mkdir -p $MOLD_WORKSPACE_DIR
  itksnap-wt \
    -lsm $MOLD_BINARY -psn "Mold Binary" \
    -laa $MOLD_MRI_N4 -psn "Mold MRI" -props-set-transform $MOLD_RIGID_MAT \
    -las $MOLD_MRI_MASK_MOLDSPC \
    -o $MOLD_WORKSPACE_SRC

  # Add each of the blocks to it
  for block in $(ls $ROOT/work/${id}/blockface); do
    
    set_block_vars $id $block

    itksnap-wt \
      -i $MOLD_WORKSPACE_SRC \
      -laa $BF_RECON_NII -psn ${block} -ta ${block} -props-set-mcd RGB \
      -o $MOLD_WORKSPACE_SRC

  done

  # Add a layer for retrieving optimal viewing orientation
  itksnap-wt \
    -i $MOLD_WORKSPACE_SRC \
    -laa $MOLD_MRI_N4 -psn "Best Viewport" -ta "Viewport" -props-set-transform $MOLD_RIGID_MAT \
    -o $MOLD_WORKSPACE_SRC
}

function process_mri_all()
{
  # Process the individual blocks
  while read -r id orient args; do

    # Submit the jobs
    qsub $QSUBOPT -N "mri_reg_${id}" \
      -l h_vmem=8G -l s_vmem=8G \
      $0 process_mri $id $orient $args

  done < $MDIR/specimen.txt

  # Wait for completion
  qsub $QSUBOPT -b y -sync y -hold_jid "mri_reg_*" /bin/sleep 0
}


function register_blockface()
{
  # Read all the arguments
  #  zpos: offset of the block in z (mm)
  #  flip: 3-digit code (010 means flip y)
  #  rot_init, dx_init, dy_init: initial in-plane transform
  read -r id block args <<< "$@"

  # Get the variables
  set_block_vars $id $block

  mkdir -p $BF_REG_DIR

  # Make sure the manual workspace exists
  if [[ ! -f $MOLD_WORKSPACE_RES ]]; then
    echo "Missing manual matching $MOLD_WORKSPACE_RES"
    exit
  fi

  # Extract the transformation that maps the blockface into the mold space
  itksnap-wt -i $MOLD_WORKSPACE_RES -lpt ${block} -props-get-transform \
    | awk '$1 == "3>" {print $2,$3,$4,$5}' \
    > $BF_TOMOLD_MANUAL_RIGID

  # Extract the green channel from the blockface image
  c3d -verbose -mcs $BF_RECON_NII -pop -stretch 0 255 255 0 -o $BF_MRILIKE

  # Reslice the mold MRI into the space of the blockface image
  greedy -d 3 -rf $BF_MRILIKE \
    -rm $MOLD_MRI_N4 $MRI_TO_BF_INIT \
    -ri LABEL 0.2vox -rm $MOLD_MRI_MASK_NATIVESPC $MRI_TO_BF_INIT_MASK \
    -r $BF_TOMOLD_MANUAL_RIGID,-1 $MOLD_RIGID_MAT

  # Perform the rigid, then affine registration
  greedy -d 3 -a -dof 6 -i $MRI_TO_BF_INIT $BF_MRILIKE \
    -gm $MRI_TO_BF_INIT_MASK -o $BF_TO_MRI_RIGID \
    -m NCC 4x4x4 -n 60x40x0 -ia-identity

  greedy -d 3 -a -dof 12 -i $MRI_TO_BF_INIT $BF_MRILIKE \
    -gm $MRI_TO_BF_INIT_MASK -o $BF_TO_MRI_AFFINE \
    -m NCC 4x4x4 -n 60x40x0 -ia $BF_TO_MRI_RIGID

  # Save a workspace with the registration result
  itksnap-wt \
    -laa $MRI_TO_BF_INIT -psn "MRI" -las $MRI_TO_BF_INIT_MASK \
    -laa $BF_MRILIKE -psn "BF_MRILIKE_NOREG" \
    -laa $BF_MRILIKE -psn "BF_MRILIKE" -props-set-transform $BF_TO_MRI_AFFINE \
    -laa $BF_RECON_NII -psn "BF" -props-set-transform $BF_TO_MRI_AFFINE -props-set-mcd RGB \
    -o $BF_TO_MRI_WORKSPACE

  # Reslice the MRI into block space using the affine registration result
  greedy -d 3 -rf $BF_MRILIKE \
    -rm $MOLD_MRI_N4 $MRI_TO_BF_AFFINE \
    -ri LABEL 0.2vox -rm $MOLD_MRI_MASK_NATIVESPC $MRI_TO_BF_AFFINE_MASK \
    -r $MRI_TO_BF_AFFINE_FULL

  # Reslice the high-resolution MRI as well. Also reslice the high-resolution MRI mask, 
  # so we can perform registration to histology later
  greedy -d 3 -rf $BF_MRILIKE -rm $HIRES_MRI $HIRES_MRI_TO_BF_AFFINE \
    -r $HIRES_TO_BF_AFFINE_FULL

  # For some reason Greedy is throwing up errors if I c
  greedy -d 3 -rf $BF_MRILIKE \
    -rm $HIRES_MRI $HIRES_MRI_TO_BF_WARPED \
    -ri NN -rm $HIRES_MRI_REGMASK $HIRES_MRI_MASK_TO_BF_WARPED \
    -r $HIRES_TO_BF_WARP_FULL

  # Create a workspace native to the blockface image
  itksnap-wt \
    -laa $BF_RECON_NII -psn "Blockface" \
    -laa $MRI_TO_BF_AFFINE -psn "Mold MRI" \
    -las $MRI_TO_BF_AFFINE_MASK -psn "Mold Mask" \
    -laa $HIRES_MRI_TO_BF_WARPED -psn "Hires MRI Warped" \
    -las $HIRES_MRI_MASK_TO_BF_WARPED -psn "Hires Mask" \
    -o $MRI_TO_BF_WORKSPACE
}


function register_blockface_all()
{
  # Process the individual blocks
  while read -r id block args; do

    # Submit the jobs
    qsub $QSUBOPT -N "reg_bf_${id}_${block}" \
      -l h_vmem=8G -l s_vmem=8G \
      $0 register_blockface $id $block

  done < $MDIR/blockface_param.txt

  # Wait for completion
  qsub $QSUBOPT -b y -sync y -hold_jid "recon_bf_*" /bin/sleep 0
}


function main()
{
  # Perform MRI registration (mold to hires)
  process_mri_all

  # Reconstruct blockface series
  recon_blockface_all

  # Register blockface to MRI
}

# Main entrypoint into script
COMMAND=$1
if [[ ! $COMMAND ]]; then
  main
else
  shift
  $COMMAND "$@"
fi
