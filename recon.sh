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
QSUBOPT="-cwd -V -j y -o $ROOT/dump ${RECON_QSUB_OPT}"

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
  HIRES_MRI_REGMASK_MANUAL=$MANUAL_DIR/hires_to_mold/${id}_mri_hires_mask.nii.gz

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
  HIRES_MRI_REGMASK=$MRI_WORK_DIR/${id}_mri_hires_mask.nii.gz
  RESLICE_MOLD_TO_HIRES=$MRI_WORK_DIR/${id}_mri_mold_reslice_to_hires.nii.gz

  # Workspaces for mold-blockface preregistration
  MOLD_WORKSPACE_DIR=$MANUAL_DIR/bf_to_mold
  MOLD_WORKSPACE_SRC=$MANUAL_DIR/bf_to_mold/${id}_mri_bf_to_mold_input.itksnap
  MOLD_WORKSPACE_RES=$MANUAL_DIR/bf_to_mold/${id}_mri_bf_to_mold_result.itksnap

  # Rotation of the holder around z axis to have the right orientation for viewingw
  MOLD_REORIENT_VIS=$MRI_WORK_DIR/${id}_mold_vis.mat
  HIRES_MRI_VIS_REFSPACE=$MRI_WORK_DIR/${id}_mri_hires_vis_refspace.nii.gz
  HIRES_MRI_VIS=$MRI_WORK_DIR/${id}_mri_hires_vis.nii.gz

  # Location of the histology data in the cloud
  SPECIMEN_HISTO_GCP_ROOT="gs://mtl_histology/${id}/histo_proc"
  SPECIMEN_HISTO_LOCAL_ROOT="$ROOT/input/${id}/histo_proc"

  # Location where to place splats
  SPECIMEN_SPLAT_DIR=$ROOT/work/$id/historeg/whole
}

function set_specimen_density_vars()
{

  # Read the parameters
  read -r id stain model args <<< "$@"

  # Splat for the current density in vis space
  SPECIMEN_DENSITY_SPLAT_VIS=${SPECIMEN_SPLAT_DIR}/${id}_density_${stain}_${model}.nii.gz

  # The workspace with that
  SPECIMEN_DENSITY_SPLAT_VIS_WORKSPACE=${SPECIMEN_SPLAT_DIR}/${id}_density_${stain}_${model}.itksnap
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

  # Optional manually generated random forest training file for segmentation of the
  # block from the background. If absent, the global rf training file will be used
  BF_CUSTOM_RFTRAIN=$MANUAL_DIR/bf_rftrain/${id}_${block}_rf.dat

  # Global blockface training file
  BF_GLOBAL_RFTRAIN=$ROOT/manual/common/blockface_rf.dat

  # MRI-like image extracted from blockface
  BF_MRILIKE=$BF_REG_DIR/${id}_${block}_blockface_mrilike.nii.gz
  BF_ICEMASK=$BF_REG_DIR/${id}_${block}_blockface_icemask.nii.gz
  BF_MRILIKE_UNMASKED=$BF_REG_DIR/${id}_${block}_blockface_mrilike_unmasked.nii.gz

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

  # Transforms to take blockface space to hires MRI space 
  BF_TO_MRI_AFFINE_FULL="$MOLD_RIGID_MAT,-1 $BF_TOMOLD_MANUAL_RIGID $BF_TO_MRI_AFFINE"
  BF_TO_HIRES_AFFINE_FULL="$HIRES_TO_MOLD_AFFINE,-1 $BF_TO_MRI_AFFINE_FULL"
  BF_TO_HIRES_FULL="$MOLD_TO_HIRES_WARP $BF_TO_HIRES_AFFINE_FULL"

  # Workspace of MRI in BF space
  MRI_TO_BF_WORKSPACE=$BF_REG_DIR/${id}_${block}_mri_to_bf.itksnap

  # Location where stack_greedy is run
  HISTO_REG_DIR=$ROOT/work/$id/historeg/$block

  # Data extracted from the histology matching spreadsheets
  HISTO_MATCH_MANIFEST=$HISTO_REG_DIR/match_manifest.txt
  HISTO_RECON_MANIFEST=$HISTO_REG_DIR/recon_manifest.txt

  # Location where stack_greedy is run
  HISTO_RECON_DIR=$HISTO_REG_DIR/recon

  # Location of splatted files
  HISTO_SPLAT_DIR=$HISTO_REG_DIR/splat

  # Splatted files
  HISTO_NISSL_RGB_SPLAT_MANIFEST=$HISTO_SPLAT_DIR/${id}_${block}_nissl_rgb_splat_manifest.txt
  HISTO_NISSL_RGB_SPLAT_PATTERN=$HISTO_SPLAT_DIR/${id}_${block}_nissl_rgb_splat_%s.nii.gz
  HISTO_NISSL_MRILIKE_SPLAT_MANIFEST=$HISTO_SPLAT_DIR/${id}_${block}_nissl_mrilike_splat_manifest.txt
  HISTO_NISSL_MRILIKE_SPLAT_PATTERN=$HISTO_SPLAT_DIR/${id}_${block}_nissl_mrilike_splat_%s.nii.gz
  HISTO_NISSL_SPLAT_WORKSPACE=$HISTO_SPLAT_DIR/${id}_${block}_nissl_rgb_splat.itksnap

  # Reference images for the splatting
  HISTO_NISSL_SPLAT_BF_MRILIKE=$HISTO_SPLAT_DIR/${id}_${block}_nissl_splat_bf_mrilike.nii.gz
  HISTO_NISSL_SPLAT_BF_MRILIKE_EDGES=$HISTO_SPLAT_DIR/${id}_${block}_nissl_splat_bf_mrilike_edges.nii.gz

  # Files exported to the segmentation server. These should be stored in a convenient
  # to copy location 
  HISTO_AFFINE_X16_DIR=$ROOT/export/affine_x16/${id}/${block}

  # Where histology-derived density maps are stored
  HISTO_DENSITY_DIR=$ROOT/work/$id/histomaps/$block
}

# Set block-level density variables
function set_block_density_vars()
{
  # Read the parameters
  read -r id block stain model args <<< "$@"

  # Set block variables
  set_block_vars $id $block

  # Splatted densities (patterns)
  HISTO_DENSITY_BASENAME=$HISTO_SPLAT_DIR/${id}_${block}_density_${stain}_${model}
  HISTO_DENSITY_SPLAT_MANIFEST=${HISTO_DENSITY_BASENAME}_rgb_splat_manifest.txt
  HISTO_DENSITY_SPLAT_IMG=${HISTO_DENSITY_BASENAME}_rgb_splat.nii.gz
  HISTO_DENSITY_SPLAT_IMG_TOHIRES=${HISTO_DENSITY_BASENAME}_rgb_splat_tohires.nii.gz

  # Splatted images from which densities are derived
  HISTO_DENSITY_SRC_BASENAME=$HISTO_SPLAT_DIR/${id}_${block}_densitysrc_${stain}_${model}
  HISTO_DENSITY_SRC_SPLAT_MANIFEST=${HISTO_DENSITY_SRC_BASENAME}_rgb_splat_manifest.txt
  HISTO_DENSITY_SRC_SPLAT_IMG=${HISTO_DENSITY_SRC_BASENAME}_rgb_splat.nii.gz
}


# Set variables for a histology slice. 
function set_ihc_slice_vars()
{
  # Read the slice parameters
  read -r id block svs stain section slice args <<< "$@"

  # Generate a unique slide id (with all information of this slide)
  SLIDE_ID=$(printf %s_%s_%s_%03d_%02d $id $block $stain $section $slice)

  # Local preproc directory for the slide
  SLIDE_LOCAL_PREPROC_DIR=$SPECIMEN_HISTO_LOCAL_ROOT/$svs/preproc

  # Local density directory for the slide
  SLIDE_LOCAL_DENSITY_DIR=$SPECIMEN_HISTO_LOCAL_ROOT/$svs/density

  # The location of the tear-fixed slide
  SLIDE_TEARFIX=$SLIDE_LOCAL_PREPROC_DIR/${svs}_tearfix.nii.gz

  # The location of the RGB thumbnail
  SLIDE_THUMBNAIL=$SLIDE_LOCAL_PREPROC_DIR/${svs}_thumbnail.tiff

  # The location of the resolution descriptor
  SLIDE_RAW_RESOLUTION_FILE=$SLIDE_LOCAL_PREPROC_DIR/${svs}_resolution.txt

  # Long name of the slide
  SLIDE_LONG_NAME=$(printf "%s_%s_%02d_%02d_%s" $id $block $section $slice $stain)

  # Google cloud destinations for stuff that goes there
  GSURL_RECON_BASE=gs://mtl_histology/${id}/histo_proc/${svs}/recon
  SLIDE_RAW_AFFINE_MATRIX_GSURL=$GSURL_RECON_BASE/${svs}_recon_iter10_affine.mat
}

# Set variables for a particular density map
function set_ihc_slice_density_vars()
{
  # Read the density map parameters
  read -r svs stain model args <<< "$@"

  # Histology density map (rsynced from cloud)
  SLIDE_DENSITY_MAP=$SLIDE_LOCAL_DENSITY_DIR/${svs}_${stain}_${model}_densitymap.nii.gz

  # Thresholded density map
  SLIDE_DENSITY_MAP_THRESH=$HISTO_DENSITY_DIR/${SLIDE_LONG_NAME?}_${model}_densitymap_thresh.nii.gz
}

# Locate the SVS file on histology drive
function get_slide_url()
{
  local SVS=${1?}
  local URLLIST=$ROOT/input/histology/slide_src.txt

  for url in $(cat $URLLIST); do
    local x=$(basename $url | sed -e "s/\..*//")
    if [[ $x == $SVS ]]; then
      echo $url
    fi
  done
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

  RGBDIR=$TMPDIR/$id/$block
  mkdir -p $RGBDIR

  # Trim the block and split the color channels
  # Crop region, scale by needed factor, split into RGB
  for fn in $(cat $BF_SLIDES); do

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

  # Get the coordinate of the image center (same for all slices)
  ctrpos_x=$(c2d $(cat $BF_SLIDES | head -n 1) -probe 50% | awk '{print $5}')
  ctrpos_y=$(c2d $(cat $BF_SLIDES | head -n 1) -probe 50% | awk '{print $6}')

  # Perform registration between all pairs of slides
  REGDIR=$TMPDIR/$id/$block/reg
  mkdir -p $REGDIR

  # Initialize the matrix chain
  matchain=

  local N=$(cat $BF_SLIDES | wc -l)
  for ((i=1; i<$N;i++)); do
    
    fn_fix=$(cat $BF_SLIDES | head -n $i | tail -n 1)
    fn_mov=$(cat $BF_SLIDES | head -n $((i+1)) | tail -n 1)

    matfile=$REGDIR/mat_raw_${i}.mat
    post_thresh_mat=$REGDIR/mat_post_thresh_${i}.mat

    # Perform registration
    refimg=$RGBDIR/rgb00_${fn_fix/.jpg/.png}
    greedy -d 2 \
      -i $RGBDIR/rgb00_${fn_fix/.jpg/.png} $RGBDIR/rgb00_${fn_mov/.jpg/.png} \
      -i $RGBDIR/rgb01_${fn_fix/.jpg/.png} $RGBDIR/rgb01_${fn_mov/.jpg/.png} \
      -i $RGBDIR/rgb02_${fn_fix/.jpg/.png} $RGBDIR/rgb02_${fn_mov/.jpg/.png} \
      -m NCC 4x4 -a -n 40x40 -o $matfile

    # Compute the displacement of the center point, does it exceed threshold?
    ctrdsp=$(cat $matfile | awk -v x=$ctrpos_x -v y=$ctrpos_y  \
      '{ q[NR]=$1*x+$2*y+$3 } END { print sqrt((q[1]-x)^2+(q[2]-y)^2) }')

    # Does it exceed threshold
    isreal=$(echo $ctrdsp 16.0 | awk '{print $1 >= $2}')
    if [[ $isreal -gt 0 ]]; then
      cp -av $matfile $post_thresh_mat
      matchain="$post_thresh_mat $matchain"
      echo "SLICE $((i+1)) to SLICE $i displacement $ctrdsp"
    fi

    # Apply the transformation
    if [[ $matchain ]]; then
      greedy -d 2 -rf $refimg \
        -rm $RGBDIR/rgb00_${fn_mov/.jpg/.png} $RGBDIR/reg_rgb00_${fn_mov/.jpg/.png} \
        -rm $RGBDIR/rgb01_${fn_mov/.jpg/.png} $RGBDIR/reg_rgb01_${fn_mov/.jpg/.png} \
        -rm $RGBDIR/rgb02_${fn_mov/.jpg/.png} $RGBDIR/reg_rgb02_${fn_mov/.jpg/.png} \
        -r $matchain
    else
      cp -av $RGBDIR/rgb00_${fn_mov/.jpg/.png} $RGBDIR/reg_rgb00_${fn_mov/.jpg/.png} 
      cp -av $RGBDIR/rgb01_${fn_mov/.jpg/.png} $RGBDIR/reg_rgb01_${fn_mov/.jpg/.png}
      cp -av $RGBDIR/rgb02_${fn_mov/.jpg/.png} $RGBDIR/reg_rgb02_${fn_mov/.jpg/.png} 
    fi

    # Copy the first slice verbatim
    if [[ $i -eq 1 ]]; then
      cp -av $RGBDIR/rgb00_${fn_fix/.jpg/.png} $RGBDIR/reg_rgb00_${fn_fix/.jpg/.png} 
      cp -av $RGBDIR/rgb01_${fn_fix/.jpg/.png} $RGBDIR/reg_rgb01_${fn_fix/.jpg/.png}
      cp -av $RGBDIR/rgb02_${fn_fix/.jpg/.png} $RGBDIR/reg_rgb02_${fn_fix/.jpg/.png} 
    fi

  done

  # Flip?
  FLIP=$(echo $block | cut -c 4-4 | sed -e "s/a//" -e "s/p/-flip z/")

  c3d \
    -verbose \
    $RGBDIR/reg_rgb00*.png -tile z -popas R \
    $RGBDIR/reg_rgb01*.png -tile z -popas G \
    $RGBDIR/reg_rgb02*.png -tile z -popas B \
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

  # Generate a mask for the high-res MRI
  if [[ -f $HIRES_MRI_REGMASK_MANUAL ]]; then
    # Copy the user's manual mask
    cp -av $HIRES_MRI_REGMASK_MANUAL $HIRES_MRI_REGMASK
  else
    # Create a mask that is all ones
    c3d $HIRES_MRI -cmv -thresh -inf inf 1 0 -o $HIRES_MRI_REGMASK
  fi

  # Registration with high-resolution image as fixed, low-resolution as moving, lots of smoothness
  greedy -d 3 -i $HIRES_MRI $MOLD_MRI_N4 -it $HIRES_TO_MOLD_AFFINE,-1 \
    -o $MOLD_TO_HIRES_WARP -oroot $MOLD_TO_HIRES_ROOT_WARP \
    -sv -s 3mm 0.2mm -m NCC 8x8x8 -n 100x100x100x40 -gm $HIRES_MRI_REGMASK \
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
  # Read an optional regular expression from command line
  REGEXP=$1

  # Process the individual blocks
  cat $MDIR/moldmri_src.txt | grep "$REGEXP" | while read -r id dir orient args; do

    # Submit the jobs
    qsub $QSUBOPT -N "mri_reg_${id}" \
      -l h_vmem=8G -l s_vmem=8G \
      $0 process_mri $id $orient $args

  done

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

  # Look up the random forest to use for the BF to MRI mapping
  local RFTRAIN=$BF_CUSTOM_RFTRAIN
  if [[ ! -f $RFTRAIN ]]; then
    RFTRAIN=$BF_GLOBAL_RFTRAIN
  fi

  # Extract the green channel from the blockface image. We generate an MRI-like
  # image by taking the foreground of the BF computed using random forest and 
  # multiplying by the inverse green channel which captures gray/white contrast
  c3d -verbose -mcs $BF_RECON_NII -popas B -popas G -popas R \
    -push R -push G -push B -rf-param-patch 3x3x1 -rf-apply $RFTRAIN \
    -stretch 0 1 1 0 -o $BF_ICEMASK \
    -push G -stretch 0 255 255 0 -o $BF_MRILIKE_UNMASKED \
    -times -o $BF_MRILIKE

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
  # Read an optional regular expression from command line
  REGEXP=$1

  # Process the individual blocks
  cat $MDIR/blockface_param.txt | grep "$REGEXP" | while read -r id block args; do

    # Submit the jobs
    qsub $QSUBOPT -N "reg_bf_${id}_${block}" \
      -l h_vmem=8G -l s_vmem=8G \
      $0 register_blockface $id $block

  done

  # Wait for completion
  qsub $QSUBOPT -b y -sync y -hold_jid "reg_bf_*" /bin/sleep 0
}


function rsync_histo_proc()
{
  read -r id args <<< "$@"

  set_specimen_vars $id

  # Create some exclusions
  local EXCL=".*_x16\.png|.*_x16_pyramid\.tiff|.*mrilike\.nii\.gz|.*affine\.mat|.*densitymap\.tiff"
  mkdir -p $SPECIMEN_HISTO_LOCAL_ROOT
  gsutil rsync -R -x "$EXCL" $SPECIMEN_HISTO_GCP_ROOT/ $SPECIMEN_HISTO_LOCAL_ROOT/
}

function rsync_histo_all()
{
  REGEXP=$1

  cat $MDIR/histo_matching.txt | grep "$REGEXP" | while read -r id args; do

    rsync_histo_proc $id

  done
}
  

function recon_histology()
{
  # What specimen and block are we doing this for?
  read -r id block args <<< "$@"

  # Make sure data is synced. NOTE: this is slowing things down. Run by hand
  ### rsync_histo_proc $id

  # Set the block variables
  set_block_vars $id $block

  # Create directories
  mkdir -p $HISTO_SPLAT_DIR $HISTO_RECON_DIR $HISTO_REG_DIR

  # Slice thickness. If this ever becomes variable, read this from the blockface_param file
  THK="0.05"
  
  # Match the id in the manifest
  url=$(cat $MDIR/histo_matching.txt | awk -v id=$id '$1 == id {print $2}')
  if [[ ! $url ]]; then
    echo "Missing histology matching data in Google sheets"
    return -1
  fi

  # Load the manifest and parse for the block of interest
  curl -s "$url" 2>&1 | \
    grep -v duplicate | \
    grep -v exclude | \
    grep -v multiple | \
    awk -F, -v b=$block '$3==b {print $0}' \
    > $HISTO_MATCH_MANIFEST

  # For each slice in the manifest, determine its z coordinate. This is done by looking 
  # up the slice in the list of all slices going into the blockface image
  rm -f $HISTO_RECON_MANIFEST

  # Additional manifest: for generating RGB NISSL images
  rm -f $HISTO_NISSL_RGB_SPLAT_MANIFEST $HISTO_NISSL_MRILIKE_SPLAT_MANIFEST

  # Another file to keep track of the range of NISSL files
  local NISSL_ZRANGE=$TMPDIR/nissl_zrange.txt
  rm -f $NISSL_ZRANGE

  # Whether the block is sectioned anteriorly or posteriorly (this affects how ZPOS
  # is computed.
  # TODO: associate ZPOS with slice at the blockface stage, not this late in the process
  local ZFLIP=$(echo $block | cut -c 4-4 | sed -e "s/a/0/" -e "s/p/1/")

  while IFS=, read -r svs stain dummy section slice args; do

    # If the slice number is not specified, fill in missing information and generate warning
    if [[ ! $slice ]]; then
      echo "WARNING: missing slice for $svs in histo matching Google sheet"
      if [[ $stain == "NISSL" ]]; then slice=10; else slice=8; fi
    fi

    # Set the variables
    set_ihc_slice_vars $id $block $svs $stain $section $slice $args

    # If the section number is not specified, then skip this line
    if [[ ! $section ]]; then
      echo "WARNING: missing section for $svs in histo matching Google sheet"
      continue
    fi

    # Make sure the preprocessing data for this slice exists, if not issue a warning
    if [[ ! -f $SLIDE_TEARFIX ]]; then
      echo "WARNING: missing TEARFIX file for $svs"
      continue
    fi

    # Generate the pattern to search for
    SEARCH_PAT=$(printf "%s_%02d_%02d" $block $section $slice)

    # Get the z-position of this slice in the world coordinates of the blockface stack nii
    if [[ $ZFLIP -eq 0 ]]; then
      ZPOS=$(grep -n "$SEARCH_PAT" $BF_SLIDES | awk -F: -v t=$THK '{print ($1-1) * t}')
    else
      ZPOS=$(grep -n "$SEARCH_PAT" $BF_SLIDES | awk -F: -v t=$THK '{print (1-$1) * t}')
    fi

    # If not found, generate warning, do not add slice
    # TODO: there are some missing blockface scans. We need a more robust way to generate 
    # z coordinates and perform stacking
    if [[ ! $ZPOS ]]; then 
      echo "WARNING: no matching blockface image for $svs"
      continue
    fi

    # Get the path to the MRI-like histology slide
    local IS_LEADER=$(echo "$stain" | sed -e "s/NISSL/1/g" -e "s/^[^1].*$/0/")
    echo $svs $ZPOS $IS_LEADER $SLIDE_TEARFIX >> $HISTO_RECON_MANIFEST

    # Add to the nissl manifest
    if [[ $stain == "NISSL" ]]; then
      echo $svs $SLIDE_THUMBNAIL >> $HISTO_NISSL_RGB_SPLAT_MANIFEST
      echo $svs $SLIDE_TEARFIX >> $HISTO_NISSL_MRILIKE_SPLAT_MANIFEST
      echo $ZPOS >> $NISSL_ZRANGE
    fi

  done < $HISTO_MATCH_MANIFEST

  # If no manifest generated, return
  if [[ ! -f $HISTO_RECON_MANIFEST ]]; then
    echo "No histology slides found"
    return -1
  fi

  # Must have "leader" NISSL slices
  if [[ ! -f $NISSL_ZRANGE ]]; then
    echo "No NISSL slides found"
    return -1
  fi

  # Run processing with stack_greedy
  stack_greedy init -M $HISTO_RECON_MANIFEST $HISTO_RECON_DIR

  # Jan 2020: the zeps=4 value seems to work better for the NCC metric, the
  # previously used value of 0.5 ended up having lots of slices skipped. But
  # need to doublecheck that this does not hurt other registrations
  stack_greedy -N recon -z 1.6 4.0 \
    -m NCC 8x8 -n 100x40x0x0 -gm-trim 8x8 -search 4000 flip 5 $HISTO_RECON_DIR

  stack_greedy -N volmatch -i $BF_MRILIKE \
    -m NCC 8x8 -n 100x40x10 -search 4000 flip 5 $HISTO_RECON_DIR

  stack_greedy -N voliter -na 20 -nd 10 -w 0.5 -wdp \
    -m NCC 8x8 -n 100x40x10 -s 3.0mm 0.5mm -sv $HISTO_RECON_DIR

  # Splat the NISSL slides if they are available
  local nissl_z0=$(cat $NISSL_ZRANGE | sort -n | head -n 1)
  local nissl_z1=$(cat $NISSL_ZRANGE | sort -n | tail -n 1)
  local nissl_zstep=0.5

  # Perform splatting at different stages
  local SPLAT_STAGES="recon volmatch voliter-20 voliter-30"
  for STAGE in $SPLAT_STAGES; do

    local OUT="$(printf $HISTO_NISSL_RGB_SPLAT_PATTERN $STAGE)"
    stack_greedy splat -o $OUT -i $(echo $STAGE | sed -e "s/-/ /g") \
      -z $nissl_z0 $nissl_zstep $nissl_z1 -S exact -ztol 0.2 -si 3.0 \
      -H -M $HISTO_NISSL_RGB_SPLAT_MANIFEST -rb 255.0 $HISTO_RECON_DIR

    local OUT="$(printf $HISTO_NISSL_MRILIKE_SPLAT_PATTERN $STAGE)"
    stack_greedy splat -o $OUT -i $(echo $STAGE | sed -e "s/-/ /g") \
      -z $nissl_z0 $nissl_zstep $nissl_z1 -S exact -ztol 0.2 -si 3.0 \
      -H -M $HISTO_NISSL_MRILIKE_SPLAT_MANIFEST -rb 0.0 $HISTO_RECON_DIR

  done

  # Create a blockface reference image that has the same dimensions as the
  # splatted images. This will be used to extract edges
  c3d $(printf $HISTO_NISSL_MRILIKE_SPLAT_PATTERN volmatch) \
    $BF_MRILIKE -int 0 -reslice-identity -o $HISTO_NISSL_SPLAT_BF_MRILIKE \
    -as X -slice z 0:-1 -foreach -canny 0.4x0.4x0.0mm 0.2 0.2 -endfor -tile z \
    -insert X 1 -copy-transform -o $HISTO_NISSL_SPLAT_BF_MRILIKE_EDGES

  # Create an ITK-SNAP workspace
  itksnap-wt \
    -lsm "$(printf $HISTO_NISSL_RGB_SPLAT_PATTERN voliter-30)" \
    -psn "NISSL voliter-30" -props-set-contrast LINEAR 0.5 1.0 -props-set-mcd rgb \
    -laa "$(printf $HISTO_NISSL_RGB_SPLAT_PATTERN voliter-20)" \
    -psn "NISSL voliter-20" -props-set-contrast LINEAR 0.5 1.0 -props-set-mcd rgb \
    -laa "$(printf $HISTO_NISSL_MRILIKE_SPLAT_PATTERN voliter-30)" \
    -psn "MRIlike voliter-30" -props-set-contrast LINEAR 0 0.2 \
    -laa "$(printf $HISTO_NISSL_MRILIKE_SPLAT_PATTERN voliter-20)" \
    -psn "MRIlike voliter-20" -props-set-contrast LINEAR 0 0.2 \
    -laa $HIRES_MRI_TO_BF_WARPED -psn "MRI" -props-set-contrast LINEAR 0 0.5 \
    -laa $HISTO_NISSL_SPLAT_BF_MRILIKE -psn "Blockface (MRI-like)" -props-set-contrast LINEAR 0.5 1.0 \
    -laa $BF_RECON_NII -psn "Blockface" -props-set-contrast LINEAR 0.0 0.5 -props-set-mcd rgb \
    -las $HISTO_NISSL_SPLAT_BF_MRILIKE_EDGES \
    -o $HISTO_NISSL_SPLAT_WORKSPACE


}

function recon_histo_all()
{
  # Read an optional regular expression from command line
  REGEXP=$1

  # Process the individual blocks
  cat $MDIR/blockface_param.txt | grep "$REGEXP" | while read -r id block args; do

    # Submit the jobs
    qsub $QSUBOPT -N "recon_histo_${id}_${block}" \
      -l h_vmem=8G -l s_vmem=8G \
      $0 recon_histology $id $block

  done

  # Wait for completion
  qsub $QSUBOPT -b y -sync y -hold_jid "recon_histo_*" /bin/sleep 0
}

# ---------------------------------------------------
# PREPARE matrices for sending to the GCP for display
# ---------------------------------------------------
function upload_histo_recon_results()
{
  # What specimen and block are we doing this for?
  read -r id block args <<< "$@"

  # Set the block variables
  set_block_vars $id $block

  # Create output directory
  mkdir -p $HISTO_AFFINE_X16_DIR

  # Get the transformation into the viewport space
  local VP_AFFINE=$TMPDIR/viewport_affine.mat
  itksnap-wt -i $MOLD_WORKSPACE_RES -lpt Viewport -props-get-transform \
    | awk '$1 == "3>" {print $2,$3,$4,$5}' \
    > $VP_AFFINE

  # Get the 3D transformation from block space into viewport space
  local VP_FULL=$TMPDIR/viewport_full.mat
  c3d_affine_tool \
    $BF_TO_MRI_AFFINE $BF_TOMOLD_MANUAL_RIGID -mult \
    $MOLD_RIGID_MAT -inv $VP_AFFINE -mult -mult \
    -o $VP_FULL

  # Extract the 2D portion of the transformation
  local VP_FULL_AXIAL=$TMPDIR/viewport_axial.mat
  cat $VP_FULL | awk '\
    NR==1 { print $1,$2,0,$4 } \
    NR==2 { print $1,$2,0,$4 } \
    NR==3 { print 0,0,1,0 } \
    NR==4 { print 0,0,0,1 }' > $VP_FULL_AXIAL

  # Get the corresponding rotation
  local VP_FULL_AXIAL_ROT=$TMPDIR/viewport_axial_rot.mat
  c3d_affine_tool $VP_FULL_AXIAL -info-full | grep -A 3 "Rotation matrix" \
    | grep -v "Rotation" > $VP_FULL_AXIAL_ROT

  # Compute the determinant
  local VP_FULL_AXIAL_ROT_DET=$( \
    cat $VP_FULL_AXIAL_ROT | awk ' \
      NR==1 { a = $1; b = $2 } \
      NR==2 { c = $1; d = $2 } \
      END { if (a * d - b * c > 0.0) { print 1 } else { print -1 } }')

  # If negative determinant, multiply by x-flip
  local VP_FULL_AXIAL_ROT_FLIP=$TMPDIR/viewport_axial_rot_flip.mat
  if [[ $VP_FULL_AXIAL_ROT_DET == "-1" ]]; then
    cat $VP_FULL_AXIAL_ROT | awk '\
      NR==1 { print -$1, $2, -$3 }
      NR>1 { print -$1,$2,$3 } ' > $VP_FULL_AXIAL_ROT_FLIP
  else
    cp $VP_FULL_AXIAL_ROT $VP_FULL_AXIAL_ROT_FLIP
  fi

  # Parse over the histology slices
  while IFS=, read -r svs stain dummy section slice args; do

    # If the slice number is not specified, fill in missing information and generate warning
    if [[ ! $slice ]]; then
      echo "WARNING: missing slice for $svs in histo matching Google sheet"
      if [[ $stain == "NISSL" ]]; then slice=10; else slice=8; fi
    fi

    set_ihc_slice_vars $id $block $svs $stain $section $slice $args

    # Get the last affine transform
    local AFF_TO_MRI=$HISTO_RECON_DIR/vol/iter10/affine_refvol_mov_${svs}_iter10.mat
    if [[ ! -f $AFF_TO_MRI ]]; then
      echo "WARNING: missing stack_greedy result for $svs"
      continue
    fi

    # Multiply the two matrices. Since we don't have c2d_affine_tool, we have to
    # do this by hand, which is uggly. 
    local FN_FULL_MATRIX=$TMPDIR/full.mat
    cat $AFF_TO_MRI $VP_FULL_AXIAL_ROT_FLIP | awk '\
      NR==1 { a11=$1; a12=$2; a13=$3 } \
      NR==2 { a21=$1; a22=$2; a23=$3 } \
      NR==4 { b11=$1; b12=$2; b13=$3 } \
      NR==5 { b21=$1; b22=$2; b23=$3 } \
      END { printf "%f %f %f \n %f %f %f \n 0 0 1 \n", \
              a11 * b11 + a12 * b21, a11 * b12 + a12 * b22, a11 * b13 + a12 * b23 + a13, \
              a21 * b11 + a22 * b21, a21 * b12 + a22 * b22, a21 * b13 + a22 * b23 + a23 }' \
              > $FN_FULL_MATRIX

    # Work out the transformation that will keep the center of the image in the same place
    # (these are comma-separated dimensions)
    local RAW_DIMS=($(cat $SLIDE_RAW_RESOLUTION_FILE \
      | grep dimensions | awk -F'),' '{print $1}' \
      | awk -F ': ...' '{print $2}' | sed -e "s/,//g"))

    # Get the centers
    local RAW_CTRS=($(echo ${RAW_DIMS[*]} | awk '{print $1/2.0, $2/2.0}'))

    cat $FN_FULL_MATRIX | awk -v cx=${RAW_CTRS[0]} -v cy=${RAW_CTRS[1]} '\
        NR==1 {print $1, $2, cx - $1*cx - $2 * cy} \
        NR==2 {print $1, $2, cy - $1*cx - $2 * cy} \
        NR==3 {print 0,0,1} ' > $SLIDE_RAW_AFFINE_MATRIX

    # Copy this matrix to its destination
    gsutil cp $SLIDE_RAW_AFFINE_MATRIX $SLIDE_RAW_AFFINE_MATRIX_GSURL

  done < $HISTO_MATCH_MANIFEST
}

function upload_histo_recon_results_all()
{
  # Read an optional regular expression from command line
  REGEXP=$1

  # Process the individual blocks
  cat $MDIR/blockface_param.txt | grep "$REGEXP" | while read -r id block args; do
    upload_histo_recon_results $id $block $args
  done
}

function recon_for_histo_manseg_all()
{
  # Read an optional regular expression from command line
  REGEXP=$1

  # Process the individual blocks
  cat $MDIR/blockface_param.txt | grep "$REGEXP" | while read -r id block args; do

    # Submit the jobs
    qsub $QSUBOPT -N "recon_manseg_${id}_${block}" \
      -l h_vmem=8G -l s_vmem=8G \
      $0 recon_for_histo_manseg $id $block

  done

  # Wait for completion
  qsub $QSUBOPT -b y -sync y -hold_jid "recon_manseg_*" /bin/sleep 0
}

# Run kubectl with additional options
function kube()
{
  kubectl --server https://kube.itksnap.org --insecure-skip-tls-verify=true "$@"
}

# Generate the tau splat images
function splat_density()
{
  # What specimen and block are we doing this for?
  read -r id block stain model args <<< "$@"

  # Set the block variables
  set_block_vars $id $block
  set_block_density_vars $id $block $stain $model

  # Generate the splat manifest file
  mkdir -p $HISTO_DENSITY_DIR
  rm -f $HISTO_DENSITY_SPLAT_MANIFEST
  while IFS=, read -r svs stain dummy section slice args; do

    # If the slice number is not specified, fill in missing information and generate warning
    if [[ ! $slice ]]; then
      echo "WARNING: missing slice for $svs in histo matching Google sheet"
      if [[ $stain == "NISSL" ]]; then slice=10; else slice=8; fi
    fi

    # Set the variables
    set_ihc_slice_vars $id $block $svs $stain $section $slice $args
    set_ihc_slice_density_vars $svs $stain $model 

    # Does the tangle density exist
    if [[ -f $SLIDE_DENSITY_MAP ]]; then

      # Apply post-processing to density map
      c2d -mcs $SLIDE_DENSITY_MAP -scale -1 -add -scale -1 -clip 0 inf \
        -smooth-fast 0.02mm -resample-mm 0.02x0.02mm \
        -o $SLIDE_DENSITY_MAP_THRESH

      echo $svs $SLIDE_DENSITY_MAP_THRESH >> $HISTO_DENSITY_SPLAT_MANIFEST
      echo $svs $SLIDE_THUMBNAIL >> $HISTO_DENSITY_SRC_SPLAT_MANIFEST

    fi

  done < $HISTO_MATCH_MANIFEST

  # Get the z-range
  Z0=$(cat $HISTO_RECON_DIR/config/manifest.txt | awk '{print int($2-0.5)}' | sort -n | head -n 1)
  Z1=$(cat $HISTO_RECON_DIR/config/manifest.txt | awk '{print int($2+0.5)}' | sort -n | tail -n 1)

  # Splat, with some smoothing to account for voxel size
  stack_greedy splat -o $HISTO_DENSITY_SPLAT_IMG \
    -i voliter 10 -ztol 0.6 -H \
    -z $Z0 1.0 $Z1 -M $HISTO_DENSITY_SPLAT_MANIFEST -S exact -rb 0 \
    -si 10 $HISTO_RECON_DIR 

  # Splat, with some smoothing to account for voxel size
  stack_greedy splat -o $HISTO_DENSITY_SRC_SPLAT_IMG \
    -i voliter 10 -ztol 0.6 -H \
    -z $Z0 1.0 $Z1 -M $HISTO_DENSITY_SRC_SPLAT_MANIFEST -S exact -rb 255.0 \
    $HISTO_RECON_DIR 
}

function splat_density_all()
{
  # Read required and optional parameters
  read -r stain model REGEXP args <<< "$@"

  # Process the individual blocks
  cat $MDIR/blockface_param.txt | grep "$REGEXP" | while read -r id block args; do

    # Submit the jobs
    qsub $QSUBOPT -N "splat_${stain?}_${model?}_${id}_${block}" \
      -l h_vmem=8G -l s_vmem=8G \
      $0 splat_density $id $block $stain $model

  done

  # Wait for completion
  qsub $QSUBOPT -b y -sync y -hold_jid "splat_${stain}_${model}*" /bin/sleep 0
}

function merge_splat()
{
  read -r id stain model args <<< "$@"

  set_specimen_vars $id
  set_specimen_density_vars $id $stain $model

  # Extract the orientation into visualizable MRI space
  itksnap-wt -i $MOLD_WORKSPACE_RES -lpt Viewport -props-get-transform \
    | grep '3>' | sed -e "s/3> //" \
    > $MOLD_REORIENT_VIS

  # Define the target space for final images
  c3d $MOLD_BINARY $MOLD_MRI_MASK_NATIVESPC \
    -int 0 -reslice-matrix $MOLD_REORIENT_VIS \
    -resample-mm 0.2x0.2x0.2mm -trim 20vox -o $HIRES_MRI_VIS_REFSPACE
  
  # Send the high-res MRI into the vis space
  greedy -d 3 \
    -rf $HIRES_MRI_VIS_REFSPACE -rm $HIRES_MRI $HIRES_MRI_VIS \
    -r $MOLD_REORIENT_VIS $HIRES_TO_MOLD_AFFINE $MOLD_TO_HIRES_INV_WARP

  # Collect all the blocks
  local BLOCKS=$(cat $MDIR/blockface_param.txt | awk -v s=$id '$1==s {print $2}')

  # Register everything into the "nice" MRI space
  local SPLATMAPS=""
  for block in $BLOCKS; do
    set_block_vars $id $block
    set_block_density_vars $id $block $stain $model

    if [[ -f $HISTO_DENSITY_SPLAT_IMG ]]; then

      local TMPMAP=$TMPDIR/$splat_${id}_${block}_${stain}_${model}.nii.gz
      greedy -d 3 -rf $HIRES_MRI_VIS_REFSPACE \
        -rm $HISTO_DENSITY_SPLAT_IMG $TMPMAP \
        -r $MOLD_REORIENT_VIS $HIRES_TO_MOLD_AFFINE $MOLD_TO_HIRES_INV_WARP $BF_TO_HIRES_FULL

      SPLATMAPS="$SPLATMAPS $TMPMAP"
    fi
  done

  # Combine the splat maps
  mkdir -p $SPECIMEN_SPLAT_DIR
  if [[ $SPLATMAPS != "" ]]; then
    c3d $SPLATMAPS -accum -add -endaccum -o $SPECIMEN_DENSITY_SPLAT_VIS
  fi

  # Create a merged workspace
  itksnap-wt \
    -lsm "$HIRES_MRI_VIS_REFSPACE" -psn "9.4T MRI" \
    -laa "$SPECIMEN_DENSITY_SPLAT_VIS" -psn "${stain} ${model}" \
    -props-set-colormap "hot" \
    -o $SPECIMEN_DENSITY_SPLAT_VIS_WORKSPACE
}


function merge_splat_all()
{
  # Read required and optional parameters
  read -r stain model REGEXP args <<< "$@"

  # Process the individual blocks
  cat $MDIR/moldmri_src.txt | grep "$REGEXP" | while read -r id args; do

    # Submit the jobs
    qsub $QSUBOPT -N "merge_${stain?}_${model?}_${id}" \
      -l h_vmem=8G -l s_vmem=8G \
      $0 merge_splat $id $stain $model

  done

  # Wait for completion
  qsub $QSUBOPT -b y -sync y -hold_jid "splat_${stain}_${model}*" /bin/sleep 0
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
