#!/bin/bash
set -x -e

id=${1?}
svs=${2?}
mkdir -p ./data

# Configure gsutil
gcloud auth activate-service-account --key-file /var/secrets/google/key.json
gcloud config set project cfn-cluster-test

RAWBASE="gs://mtl_histology/$id/histo_raw"
PREPROCBASE="gs://mtl_histology/$id/histo_proc/$svs/preproc"

# Locate the x16 PNG
if pngfile=$(gsutil ls "$PREPROCBASE/${svs}_x16.png"); then
  echo "x16 PNG file found for $id $svs"
  gsutil cp $pngfile ./data
elif svsfile=$(gsutil ls "$RAWBASE/${svs}.*"); then

  echo "Raw SVS file found for $id $svs"
  gsutil cp $svsfile ./data
  echo "hello"
  svslocal=$(ls ./data/${svs}.{tiff,tif,svs} || true)
  echo "svslocal=$svslocal"

  # Extract a thumbnail and a 40um resolution image
  ./process_raw_slide.py -m -i $svslocal -s ./data/${svs}

else
  echo "Raw SVS file not found for $id $svs"
  exit -1
fi

# Locate the tiff

# Run VIPS
MIDRES_PNG=./data/${svs}_x16.png
MIDRES_TIFF=./data/${svs}_x16.tiff
MIDRES_PTIFF=./data/${svs}_x16_pyramid.tiff
convert $MIDRES_PNG $MIDRES_TIFF
vips tiffsave $MIDRES_TIFF $MIDRES_PTIFF \
  --vips-progress --compression=deflate \
  --tile --tile-width=256 --tile-height=256 \
  --pyramid --bigtiff

# Upload
gsutil cp $MIDRES_PTIFF $PREPROCBASE/
