#!/bin/bash

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

# Extract a thumbnail
SUMMARY=./data/${svs}_thumbnail.tiff
LABELFILE=./data/${svs}_label.tiff
python process_raw_slide.py -i $svslocal -s ./data/${svs}

# Mid-resolution image
MIDRES=./data/${svs}_x16.png
RESFILE=./data/${svs}_resolution.txt
python process_raw_slide.py -i $svslocal -m $MIDRES > $RESFILE

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
OUTPUTS="$SUMMARY $LABELFILE $MIDRES $RESFILE $MRILIKE $TEARFIX"
for out in $OUTPUTS; do
  if [[ ! -f $out ]]; then
    echo "Failed to generate output $out"
    exit -1
  fi
done

# Upload the outputs to the bucket
if ! gsutil cp $OUTPUTS gs://mtl_histology/$id/histo_proc/${svs}/preproc/ ; then
  echo "Failed to upload results"
  exit -1
fi
