#!/bin/bash

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

# Process the individual images
for ((i=0;i<$NIMAGES;i++)); do

  # Read the input image
  IMG=${1?}
  shift

  # Process the slices
  DISPMODE=$(jq -r ".inputs[$i].display" $JSON)

  # Handle each slice
  for ((j=0;j<$SNUM;j++)); do

    # Slice command
    SVAL=$(jq -r ".slicing.positions[$j]" $JSON)
    SCMD="-slice $SAXIS $SVAL"

    # Slice filename
    SFN=$(printf "$TMPDIR/slice_img_%03d_pos_%03d.png" $i $j)
    echo $i $j $SFN >> $SLICE_LIST_FILE

    # If RGB, there is special handling
    if [[ $DISPMODE == RGB ]]; then
      c3d -mcs $IMG -foreach $SCMD -endfor -type uchar -omc $SFN
    elif [[ $DISPMODE == grayscale ]]; then
      c3d $IMG -stretch 0 99% 0 255 -clip 0 255 $SCMD -type uchar -o $SFN
    fi

    # If this is an edge image, generate edges
    if [[ $(jq -r ".inputs[$i].edges" $JSON) == "true" ]]; then
      EDGEIMG=$TMPDIR/$(printf "edges_%03d.png" $j)
      convert $SFN -canny 0x1+10%+30% +level-colors black,white -transparent black $EDGEIMG
    fi

  done

done

# Add edges and grids
for ((j=0;j<$SNUM;j++)); do

  EDGEIMG=$TMPDIR/$(printf "edges_%03d.png" $j)
  for ((i=0;i<$NIMAGES;i++)); do

    # Main image
    SFN=$(printf "$TMPDIR/slice_img_%03d_pos_%03d.png" $i $j)

    # Add the edges
    if [[ -f $EDGEIMG ]]; then
      composite -gravity center -compose screen $EDGEIMG $SFN $SFN
    fi

    # Apply a grid on the image
    apply_grid $SFN $SFN
  done
done

# Montage the images
montage -tile $NIMAGES $SNUM -geometry +5+5 -mode Concatenate \
  $(sort -k 2 $SLICE_LIST_FILE | awk '{print $3}') $OUTPUT


