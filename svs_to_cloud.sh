#!/bin/bash
set -x -e

# Globals
ROOT=/data/picsl/pauly/tau_atlas
MDIR=$ROOT/manifest

# Simple script: go through all of the Google spreadsheets and for each one, 
# find the SVS files that are 'usable' and upload them to the cloud
function process_specimen()
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
  SVSLIST=$(curl -s "$url" 2>&1 | \
    grep -v duplicate | \
    grep -v multiple | \
    awk -F, 'NR > 1 {print $1}')

  # Launch array tasks
  export SVSLIST id
  qsub -sync y -j y -o $ROOT/dump -cwd -V -t 1-$(echo $SVSLIST | wc -w) -tc 6 \
    $0 process_slide_task 
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
function process_slide()
{
  read -r id svs args <<< "$@"

  # Read the appropriate line in the source file
  read -r dummy host vol ext <<< \
    $(cat $MDIR/svs_source.txt | awk -v id=$id '$1==id {print $0}')

  # Form a URL for the source
  src_url=$(get_slide_list_single $id $host $vol $ext $svs)

  # Form a URL for the destination
  dst_url="gs://mtl_histology/HNL-11-15/histo_raw/${svs}.${ext}"

  echo "process_slide $id $svs $src_url $dst_url"


  # Check if the file exists at destination
  if gsutil -q stat $dst_url; then
    echo "destination URL exists"
  else
    time scp $src_url $TMPDIR/${svs}.${ext}
    time gsutil cp $TMPDIR/${svs}.${ext} $dst_url
  fi
}

# Process an individual task
function process_slide_task()
{
  SVS=$(echo $SVSLIST | cut -d " " -f $SGE_TASK_ID)

  # Locate the slide on the histology drive
  process_slide $id $SVS
}

# main
function main()
{
  for id in $(cat $MDIR/histo_matching.txt | awk '{print $1}'); do
    process_specimen $id
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
