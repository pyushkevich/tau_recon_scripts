#!/bin/bash
set -x -e

# Read the JSON describing the montage
JSON=${1?}
shift

# Read the output filename
OUTPUT=${1?}
shift

# Get the number of images
NIMAGES=$(jq '.inputs | length' $JSON)

# Create temp-dir for working images
TMPDIR=$(mktemp -d -t lb-XXXXXXXXXX)
SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# List of slice images
SLICE_LIST_FILE=$TMPDIR/manifest.txt

# Function to apply grid
function apply_grid()
{

  FILE=${1?}
  local OPACITY=$(jq -r ".grid.opacity" $JSON)
  local SPACING=$(jq -r ".grid.spacing" $JSON)
  local COLOR=$(jq -r ".grid.color" $JSON)
  local DIMS=$(identify $FILE | awk '{print $4}')
  local SPX=$(echo $DIMS | awk -F "[x+]" -v s=$SPACING '{printf("%.0f\n", $1 / s)}')
  local SPY=$(echo $DIMS | awk -F "[x+]" -v s=$SPACING '{printf("%.0f\n", $2 / s)}')
  bash ${SCRIPTDIR}/ashs_grid.sh -o $OPACITY -s $SPX,$SPY -c $COLOR $FILE $FILE
}

# Build the slicing command
SAXIS=$(jq -r '.slicing.axis' $JSON)
SNUM=$(jq -r '.slicing.positions | length' $JSON)

# Load images in an array
REFIMG=
for ((i=0;i<$NIMAGES;i++)); do
  IMG[$i]=${1?}
  shift

  if [[ $(jq -r ".inputs[$i].reference" $JSON) == "true" ]]; then
    REFIMG=${IMG[i]}
  fi
done

# Extract a slice from the reference image
for ((j=0;j<$SNUM;j++)); do
  # Slice position (in percent)
  SVAL=$(jq -r ".slicing.positions[$j]" $JSON)

  # Reference filename for slice
  REFSLC=$(printf $TMPDIR/refslice_%03d.nii.gz $j)

  # Extract the reference slice and equalize its dimensions
  c3d $REFIMG -slice $SAXIS $SVAL -int 0 -resample-iso min -slice z 50% -o $REFSLC
done

# Process the individual images
for ((i=0;i<$NIMAGES;i++)); do

  # Skip hidden reference images
  if [[ $(jq -r ".inputs[$i].hidden" $JSON) == "true" ]]; then
    continue
  fi

  # Process the slices
  DISPMODE=$(jq -r ".inputs[$i].display" $JSON)

  # Handle each slice
  for ((j=0;j<$SNUM;j++)); do

    # Slice command
    REFSLC=$(printf $TMPDIR/refslice_%03d.nii.gz $j)

    # Slice filename
    SFN=$(printf "$TMPDIR/slice_img_%03d_pos_%03d.png" $i $j)
    echo $i $j $SFN >> $SLICE_LIST_FILE

    # If RGB, there is special handling
    if [[ $DISPMODE == RGB ]]; then
      c3d $REFSLC -popas R -mcs ${IMG[i]} -int 0 -foreach -insert R 1 -reslice-identity -endfor -type uchar -omc $SFN
    elif [[ $DISPMODE == grayscale ]]; then
      c3d $REFSLC -popas R -mcs ${IMG[i]} -int 0 -stretch 0 99% 0 255 -clip 0 255 -insert R 1 -reslice-identity \
        -dup -dup -type uchar -omc $SFN
    fi

    # If this is an edge image, generate edges
    if [[ $(jq -r ".inputs[$i].edges" $JSON) == "true" ]]; then
      EDGEIMG=$TMPDIR/$(printf "edges_%03d.png" $j)
      EDGESIGMA=$(jq -r ".inputs[$i].edge_sigma // \"4vox\"" $JSON)
      ET1=$(jq -r ".inputs[$i].edge_threshold[0] // 1" $JSON)
      ET2=$(jq -r ".inputs[$i].edge_threshold[1] // 1" $JSON)

      # Using c2d for this because it works more consistently
      c2d $SFN -canny $EDGESIGMA $ET1 $ET2 -info -scale 255 -type uchar -o $EDGEIMG
      ### convert $SFN -canny 0x1+10%+30% +level-colors black,white -transparent black $EDGEIMG
    fi

  done
done

# Get a list of included images and positions
ARR_IMG=($(awk '{print $1}' $SLICE_LIST_FILE | sort -u -n ))
ARR_POS=($(awk '{print $2}' $SLICE_LIST_FILE | sort -u -n ))

# Add edges and grids
for j in ${ARR_POS[*]}; do

  EDGEIMG=$TMPDIR/$(printf "edges_%03d.png" $j)
  for i in ${ARR_IMG[*]}; do

    # Main image
    SFN=$(printf "$TMPDIR/slice_img_%03d_pos_%03d.png" $i $j)
    SFN2=$(printf "$TMPDIR/tmp_slice_img_%03d_pos_%03d.png" $i $j)

    # Add the edges
    if [[ -f $EDGEIMG ]]; then

      # Get the edge colors
      EDGE_R=$(jq -r ".inputs[$i].edge_color[0] // 255" $JSON)
      EDGE_G=$(jq -r ".inputs[$i].edge_color[1] // 255" $JSON)
      EDGE_B=$(jq -r ".inputs[$i].edge_color[2] // 255" $JSON)

      c2d \
        $EDGEIMG -stretch 0 255 1 0 -popas X \
        -mcs $SFN \
        -foreach -insert X 1 -copy-transform -endfor \
        -popas B -popas G -popas R \
        -push X -stretch 1 0 0 ${EDGE_R-255} -push X -push R -times -add \
        -push X -stretch 1 0 0 ${EDGE_G-255} -push X -push G -times -add \
        -push X -stretch 1 0 0 ${EDGE_B-255} -push X -push B -times -add \
        -type uchar -omc $SFN2
      cp $SFN2 $SFN
    fi

    # Apply a grid on the image
    apply_grid $SFN $SFN
  done
done

# How to sort the images
if [[ $(jq -r ".layout.transpose" $JSON) == "true" ]]; then
  SORTKEY=1
  TILING=${#ARR_POS[*]}x${#ARR_IMG[*]}
else
  SORTKEY=2
  TILING=${#ARR_IMG[*]}x${#ARR_POS[*]}
fi

# Montage the images
montage $IMAGEMAGICK_FONT_CMD -tile $TILING -geometry +5+5 -mode Concatenate \
  $(sort -k $SORTKEY $SLICE_LIST_FILE | awk '{print $3}') $OUTPUT


