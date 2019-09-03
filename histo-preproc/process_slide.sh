#!/bin/bash
set -x -e

id=${1?}
svs=${2?}

# Configure gsutil
gcloud auth activate-service-account --key-file /var/secrets/google/key.json
gcloud config set project cfn-cluster-test

# Locate the SVS
if ! svsfile=$(gsutil ls "gs://mtl_histology/$id/histo_raw/${svs}.*"); then
  echo "Raw SVS file not found for $id $svs"
  exit -1
fi

# Download the SVS to a local file
mkdir -p ./data
gsutil cp $svsfile ./data

# Find the file
if ! svslocal=$(ls ./data/${svs}.*); then
  echo "Download failed for $id $svs $svsfile"
  exit -1
fi

# Check for levels, and if there is only one level, replace the
# image with a pyramid one
LEVELS=$(python process_raw_slide.py -i $svslocal -l)
if [[ $LEVELS -eq 1 ]]; then
  mkdir -p ./data/fixflat
  mv $svslocal ./data/fixflat
  svsflat=$(ls ./data/fixflat/${svs}.*)
  vips tiffsave $svsflat $svslocal \
    --vips-progress --compression=jpeg --Q=80 \
    --tile --tile-width=256 --tile-height=256 \
    --pyramid --bigtiff
fi

# Extract a thumbnail
SUMMARY=./data/${svs}_thumbnail.tiff
LABELFILE=./data/${svs}_label.tiff
python process_raw_slide.py -i $svslocal -s ./data/${svs}

# Mid-resolution image
MIDRES=./data/${svs}_x16.png
RESFILE=./data/${svs}_resolution.txt
python process_raw_slide.py -i $svslocal -m $MIDRES > $RESFILE

# Generate a pyramid TIFF file of the x16
MIDRES_PTIFF=./data/${svs}_x16_pyramid.tiff
vips tiffsave $MIDRES $MIDRES_PTIFF \
  --vips-progress --compression=deflate \
  --tile --tile-width=256 --tile-height=256 \
  --pyramid --bigtiff

# Get the MRI-like appearance
MRILIKE=./data/${svs}_mrilike.nii.gz
TEARFIX=./data/${svs}_tearfix.nii.gz
python process_raw_slide.py -i $svslocal -o ./data/${svs}_mrilike.nii.gz -t 100

# Additional c3d processing
c2d $MRILIKE -clip 0 1 -stretch 0 1 1 0 \
  -as G -thresh 0.2 inf 1 0 -as M \
  -push G -median 11x11 -times \
  -push G -push M -replace 0 1 1 0 -times \
  -add -o $TEARFIX

# Check that each of the outputs exists
REQ_OUTPUTS="$SUMMARY $MIDRES $MIDRES_PTIFF $RESFILE $MRILIKE $TEARFIX"
ALL_OUTPUTS="$REQ_OUTPUTS $LABELFILE"
for out in $REQ_OUTPUTS; do
  if [[ ! -f $out ]]; then
    echo "Failed to generate output $out"
    exit -1
  fi
done

# Upload the outputs to the bucket
for out in $ALL_OUTPUTS; do
  if [[ -f $out ]]; then
    if ! gsutil cp $out gs://mtl_histology/$id/histo_proc/${svs}/preproc/ ; then
      echo "Failed to upload results"
      exit -1
    fi
  fi
done

# Copy the pyramid image in place of the non-pyramid one
if [[ $LEVELS -eq 1 ]]; then
  if ! gsutil cp $svslocal $svsfile; then
    echo "Failed to upload pyramid tif/svs"
    exit -1
  fi
fi
