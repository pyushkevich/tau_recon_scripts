#!/bin/bash
set -e

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
    CMD_REF_1="$REFIMG -popas R "
    CMD_REF_2="-insert R 1 -reslice-identity "
  fi
done

# Reference image commands

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
    SVAL=$(jq -r ".slicing.positions[$j]" $JSON)
    SCMD="-slice $SAXIS $SVAL -resample-iso min "

    # Slice filename
    SFN=$(printf "$TMPDIR/slice_img_%03d_pos_%03d.png" $i $j)
    echo $i $j $SFN >> $SLICE_LIST_FILE

    # If RGB, there is special handling
    if [[ $DISPMODE == RGB ]]; then
      c3d $CMD_REF_1 -mcs ${IMG[i]} -foreach $CMD_REF_2 $SCMD -endfor -type uchar -omc $SFN
    elif [[ $DISPMODE == grayscale ]]; then
      c3d $CMD_REF_1 ${IMG[i]} -stretch 0 99% 0 255 -clip 0 255 $CMD_REF_2 $SCMD -type uchar -o $SFN
    fi

    # If this is an edge image, generate edges
    if [[ $(jq -r ".inputs[$i].edges" $JSON) == "true" ]]; then
      EDGEIMG=$TMPDIR/$(printf "edges_%03d.png" $j)
      convert $SFN -canny 0x1+10%+30% +level-colors black,white -transparent black $EDGEIMG
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

    # Add the edges
    if [[ -f $EDGEIMG ]]; then

      # Get the edge color
      EDGECOLOR=$(jq -r ".inputs[$i].edge_color" $JSON)
      if [[ ! $EDGECOLOR ]]; then EDGECOLOR="white"; fi

      convert $EDGEIMG -background $EDGECOLOR -negate -alpha Shape -transparent white $TMPDIR/tmpedge.png
      convert $SFN $TMPDIR/tmpedge.png -composite $SFN
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
montage -tile $TILING -geometry +5+5 -mode Concatenate \
  $(sort -k $SORTKEY $SLICE_LIST_FILE | awk '{print $3}') $OUTPUT


