#!/bin/bash
# set -x -e

# ----------------------------------------------------
# Scripts to perform preprocessing of histology on GCP
# ----------------------------------------------------

# Globals
ROOT=/data/picsl/pauly/tau_atlas
ROOT=/Users/pauly/tk/docker/tau_atlas/tau_atlas
MDIR=$ROOT/manifest

# Get all the slide identifiers in the manifest file for a specimen
function get_specimen_manifest_slides()
{
  # What specimen and block are we doing this for?
  read -r id args <<< "$@"

  # Match the id in the manifest
  url=$(cat $MDIR/histo_matching.txt | awk -v id=$id '$1 == id {print $2}')
  if [[ ! $url ]]; then
    echo "Missing histology matching data in Google sheets"
    return -1
  fi

  # Read the relevant slides in the manifest
  curl -s "$url" 2>&1 | \
    grep -v duplicate | \
    grep -v multiple | \
    awk -F, 'NR > 1 {print $1}'
}

# Simple script: go through all of the Google spreadsheets and for each one, 
# find the SVS files that are 'usable' and upload them to the cloud
function upload_to_bucket_specimen()
{
  # What specimen and block are we doing this for?
  read -r id args <<< "$@"

  # Match the id in the manifest
  SVSLIST_FULL=$(get_specimen_manifest_slides $id)

  # Get the list of all remote slides
  FREMOTE=$(mktemp /tmp/svs-to-cloud.XXXXXX)
  gsutil ls "gs://mtl_histology/${id}/histo_raw/*.*" > $FREMOTE

  # Filter the SVS list to only include images that are not already copied
  SVSLIST=""
  for f in $SVSLIST_FULL; do
    if ! grep "histo_raw\/${f}\." $FREMOTE > /dev/null; then
      SVSLIST="$SVSLIST $f"
    fi
  done

  # Progress
  echo "Specimen ${id}: $(echo $SVSLIST | wc -w) specimens need to be uploaded"

  # Launch array tasks
  export SVSLIST id
  qsub -sync y -j y -o $ROOT/dump -cwd -V -t 1-$(echo $SVSLIST | wc -w) -tc 6 \
    $0 upload_to_bucket_slide_task 
}

# Get a complete URL to the file
function get_slide_list_single()
{
  read -r id server url fext fname <<<  "$@"
  FOLDER=$(echo "$url" | sed -e "s/ /\\\\ /g" -e "s/(/\\\\(/g" -e "s/)/\\\\)/g")
  ssh $server ls $FOLDER/${fname}.${fext} | sed -e "s/ /\\\\ /g" -e "s/(/\\\\(/g" -e "s/)/\\\\)/g" \
    -e "s/^/$server:/"
}

# Process an individual slide task
function upload_to_bucket_slide()
{
  read -r id svs args <<< "$@"

  # Read the appropriate line in the source file
  read -r dummy host vol ext <<< \
    $(cat $MDIR/svs_source.txt | awk -v id=$id '$1==id {print $0}')

  # Form a URL for the source
  src_url=$(get_slide_list_single $id $host $vol $ext $svs)

  # Form a URL for the destination
  dst_url="gs://mtl_histology/$id/histo_raw/${svs}.${ext}"

  echo "upload_to_bucket_slide $id $svs $src_url $dst_url"


  # Check if the file exists at destination
  if gsutil -q stat $dst_url; then
    echo "destination URL exists"
  else
    time scp $src_url $TMPDIR/${svs}.${ext}
    time gsutil cp $TMPDIR/${svs}.${ext} $dst_url
  fi
}

# Process an individual task
function upload_to_bucket_slide_task()
{
  SVS=$(echo $SVSLIST | cut -d " " -f $SGE_TASK_ID)

  # Locate the slide on the histology drive
  upload_to_bucket_slide $id $SVS
}

# main
function upload_to_bucket_all()
{
  for id in $(cat $MDIR/histo_matching.txt | awk '{print $1}'); do
    upload_to_bucket_specimen $id
  done
}

# List all raw images that are in manifest files and exist on the remote server
function get_specimen_cloud_raw_slides()
{
  read -r id args <<< "$@"

  # Get the list of SVS ids in the manifest
  SVSLIST_FULL=$(get_specimen_manifest_slides $id)

  # Get the list of SVS files on GCP
  FREMOTE=$(mktemp /tmp/svs-to-cloud.XXXXXX)
  gsutil ls "gs://mtl_histology/${id}/histo_raw/*.*" > $FREMOTE

  # Get the list that is in both
  SVSLIST=""
  for f in $SVSLIST_FULL; do
    if grep "histo_raw\/${f}\." $FREMOTE > /dev/null; then
      SVSLIST="$SVSLIST $f"
    fi
  done

  echo $SVSLIST
}

# Apply preprocessing to all the slides that don't have it, unless FORCE=1 
# in which case, we apply to everything brute force
function preprocess_specimen_slides()
{
  read -r id force args <<< "$@"

  # Get the list of slides that are eligible
  SVSLIST=$(get_specimen_manifest_slides $id)

  # Get a full directory dump
  FREMOTE=$(mktemp /tmp/preproc-remote-list.XXXXXX)
  gsutil ls "gs://mtl_histology/$id/histo_proc/**" > $FREMOTE

  # Check for existence of all remote files
  for svs in $SVSLIST; do

    BASE="gs://mtl_histology/$id/histo_proc/${svs}/preproc/${svs}_"

    # Check if we have to do this
    for fn in thumbnail.tiff label.tiff resolution.txt mrilike.nii.gz tearfix.nii.gz; do
      fn_full=${BASE}${fn}
      if ! grep "$fn_full" $FREMOTE; then
        force=1
      fi
    done

    if [[ $force ]]; then

      # Get a job ID
      JOB=$(echo $id $svs | md5 | cut -c 1-6)

      # Create a yaml from the template
      YAML=/tmp/preproc_${JOB}.yaml
      cat $ROOT/scripts/yaml/histo_preproc.template.yaml | \
        sed -e "s/%ID%/${id}/g" -e "s/%JOBID%/$JOB/g" -e "s/%SVS%/${svs}/g" \
        > $YAML

      # Run the yaml
      echo kubectl apply -f $YAML

    fi

  done
}

# Main entrypoint into script
COMMAND=$1
if [[ ! $COMMAND ]]; then
  main
else
  shift
  $COMMAND "$@"
fi
