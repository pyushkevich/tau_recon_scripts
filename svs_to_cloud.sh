#!/bin/bash
set -e

# ----------------------------------------------------
# Scripts to perform preprocessing of histology on GCP
# and synchronize data in GCP with local storage.
# ----------------------------------------------------

# Globals
if [[ $TAU_ATLAS_ROOT ]]; then
  . $TAU_ATLAS_ROOT/scripts/common.sh
else
  . "$(dirname $0)/common.sh"
fi

MDIR=$ROOT/manifest

# Histoannot server options
PHAS_SERVER="https://histo.itksnap.org"
PHAS_ANNOT_TASK=2
PHAS_REGEVAL_TASK=6

# Run kubectl with additional options
function kube()
{
  # kubectl --server https://kube.itksnap.org --insecure-skip-tls-verify=true "$@"
  kubectl "$@"
}

# Uses curl to print a remote URL
function curl_cat_url()
{
  local URL CURL_OPTS
  read -r URL CURL_OPTS <<< "$@"

  if [[ $CURL_SSH_HOST ]]; then
    # SSH to a remote host before getting the web-based resource
    # -n is critical here, otherwise stdin gets messed with and read does not work
    ssh -n -q -o BatchMode=yes -o StrictHostKeyChecking=no $CURL_SSH_HOST \
      curl -L -s -f --retry 4 "$CURL_OPTS" "$URL"
  else
    curl -L -s -f --retry 4 "$CURL_OPTS" "$URL"
  fi
}

# Uses curl to download a file
function curl_download_url()
{
  local URL FILE CURL_OPTS
  read -r URL FILE CURL_OPTS <<< "$@"

  echo "CURL_OPTS=$CURL_OPTS"

  if [[ $CURL_SSH_HOST ]]; then
    # SSH to a remote host before getting the web-based resource
    # -n is critical here, otherwise stdin gets messed with and read does not work
    ssh -n -q -o BatchMode=yes -o StrictHostKeyChecking=no $CURL_SSH_HOST \
      curl -L -s -f --retry 4 -o "$FILE" "$CURL_OPTS" "$URL"
  else
    curl -L -s -f --retry 4 -o "$FILE" "$CURL_OPTS" "$URL"
  fi
}

# Download the Google sheets URL for specimen to a directory
function download_histo_manifest()
{
  local id dest url args
  read -r id dest <<< "$@"

  # Match the id in the manifest
  url=$(cat $MDIR/histo_matching.txt | awk -v id=$id '$1 == id {print $2}')
  if [[ ! $url ]]; then
    echo "Missing histology matching data in Google sheets"
    return 255
  fi

  # Download the url
  if ! curl_cat_url "$url" > "$dest"; then
    echo "Unable to download $url"
    return 255
  fi


}

# Update the local copy of the histology manifest file for a single specimen/block
function update_histo_match_manifest_specimen()
{
  local id all_blocks block args

  # What specimen and block are we doing this for?
  read -r id args <<< "$@"

  # The output filename
  local HISTO_MATCH_MANIFEST_DIR=$ROOT/input/${id}/histo_manifest/
  mkdir -p $HISTO_MATCH_MANIFEST_DIR

  # Remove existing manifest files
  rm -rf $HISTO_MATCH_MANIFEST_DIR/${id}_*_histo_manifest.txt

  # Load the manifest and parse for the block of interest, put into temp file
  local TMPFILE_FULL=$TMPDIR/manifest_full_${id}.txt
  local TMPFILE_CLEAN=$TMPDIR/manifest_clean_${id}.txt

  # Download the manifest
  download_histo_manifest "$id" "$TMPFILE_FULL"

  # Check exclusions
  awk -F, '$6 !~ "duplicate|exclude" && $4 !~ "multiple" && NR > 1 {print $0}' $TMPFILE_FULL > $TMPFILE_CLEAN

  # Get the list of unique blocks
  all_blocks=$(awk -F, '{print $3}' $TMPFILE_CLEAN | sort -u)
  for block in $all_blocks; do

    # Destination for this block
    local HISTO_MATCH_MANIFEST=$HISTO_MATCH_MANIFEST_DIR/${id}_${block}_histo_manifest.txt

    # Extract the matches for this block
    local TMPFILE=$TMPDIR/manifest_${id}_${block}.txt
    awk -F, -v b=$block '$3 == b {print $0}' $TMPFILE_CLEAN > $TMPFILE

    # Read all the slices for this block
    local svs stain dummy section slice args
    while IFS=, read -r svs stain dummy section slice args; do

      # Check for incomplete lines
      if [[ ! $section || ! $stain || ! $svs ]]; then
        echo "WARNING: incomplete line '$svs,$stain,$dummy,$section,$slice,$args' in Google sheet"
        continue
      fi

      # If the slice number is not specified, fill in missing information and generate warning
      if [[ ! $slice ]]; then
        echo "WARNING: missing slice for $svs in histo matching Google sheet"
        if [[ $stain == "NISSL" ]]; then slice=10; else slice=8; fi
      fi

      echo $svs,$stain,$dummy,$section,$slice >> $HISTO_MATCH_MANIFEST
    done < $TMPFILE

    # Report for this block
    echo "Manifest for $id $block updated. Slides: $(wc -l < $HISTO_MATCH_MANIFEST)"

  done
}


# Update the local copy of the histology manifest files
function update_histo_match_manifest_all()
{
  # Specimen regexp
  REGEXP=$1

  # Process the individual blocks
  while read -r id url; do
    if [[ $id =~ $REGEXP ]]; then
      update_histo_match_manifest_specimen ${id}
    fi
  done < "$MDIR/histo_matching.txt"
}

# Get all the slide identifiers in the manifest file for a specimen
function get_specimen_manifest_slides()
{
  # What specimen are we doing this for?
  read -r id stain args <<< "$@"

  # Directory with manifest files
  local HISTO_MATCH_MANIFEST_DIR=$ROOT/input/${id}/histo_manifest/

  # Apply filters
  local AWKCMD="{print \$1}"
  if [[ $stain ]]; then
    AWKCMD="\$2==\"${stain}\" {print \$1}"
  fi
    
  # Read the relevant slides in the manifest
  awk -F, "$AWKCMD" $HISTO_MATCH_MANIFEST_DIR/${id}_*_histo_manifest.txt || echo ""
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

# Search for slides that do not yet have an entry in the histology manifest (on Google drive)
function check_for_new_slides_specimen()
{
  # What specimen and block are we doing this for?
  read -r id args <<< "$@"

  # List all of the tif files for this specimen
  local WDIR FREMOTE FLOCAL FCSV FREMOTE_IDS FMISSING_IDS
  WDIR=$(mktemp -d /tmp/slide_check.XXXXXX)
  FREMOTE=$WDIR/remote.txt
  gsutil ls gs://mtl_histology/$id/histo_raw/*.tif > $FREMOTE

  # Get a listing of remote ids
  FREMOTE_IDS=$WDIR/remote_ids.txt
  while IFS= read -r fn; do
    fn_base=$(basename $fn)
    img="${fn_base%.*}"
    echo $img >> $FREMOTE_IDS
  done < $FREMOTE

  # Create a listing of ids present in the manifest
  FCSV=$WDIR/slide_listing.csv
  download_histo_manifest "$id" "$FCSV"

  # Extract slide ids
  FLOCAL=$WDIR/local.txt
  awk -F, 'NR > 1 {print $1}' "$FCSV" > "$FLOCAL"

  # Create a difference listing
  FMISSING_IDS=$WDIR/missing.txt
  diff --new-line-format="" --unchanged-line-format="" \
    <(sort -u $FREMOTE_IDS) <(sort -u $FLOCAL) \
    > $FMISSING_IDS | :

  # For missing entries create proposed manifest line
  while IFS= read -r img; do

    # Break the filename into pieces
    local SPEC BLOCK STAIN SECTION SUF1 SUF2 MS_FIRST MS_LAST
    IFS='_' read -r SPEC BLOCK STAIN SECTION SUF1 SUF2 <<< "$img"

    # Rename stain
    STAIN=$(echo $STAIN | sed -e "s/TAU/Tau/")

    # Is this a multi-slide scan?
    if echo $SECTION | grep -E "[0-9]+-[0-9]+" > /dev/null; then

      # Read the first and last sections of the multi-slide
      IFS='-' read -r MS_FIRST MS_LAST <<< "$SECTION"

      # Read the first suffix and decypher it into an index
      MS_IDX=$(($(echo $SUF1 | sed -e "s/^R//")))

      # Get the actual section
      SECTION=$((MS_FIRST+MS_IDX-1))

      # Shift suffix
      SUF1=$SUF2
    fi

    # Determine the slice based on common rules
    SLIDEIDX=$(echo $STAIN | sed -e "s/NISSL/10/" -e "s/Tau/9/" \
            -e "s/SGR/6/" -e "s/NAB/8/" -e "s/TDP43/7/" -e "s/TDP/7/")

    # Check for duplicates
    DUPS=$(awk -F, -v b=$BLOCK -v s=$STAIN -v x=$SECTION \
      '$2==s && $3 == b && $4 == x {printf(",%s",$1)}' $FCSV)

    # Print the slide information
    echo $img,$STAIN,$BLOCK,$SECTION,$SLIDEIDX,${SUF1}${DUPS}

  done < $FMISSING_IDS
}

function check_for_new_slides_all()
{
  # Specimen regexp
  REGEXP=$1

  # Process the individual blocks
  while read -r id url; do
    if [[ $id =~ $REGEXP ]]; then
      check_for_new_slides_specimen ${id}
    fi
  done < "$MDIR/histo_matching.txt"
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
  local id dryrun force args SVSLIST FREMOTE BASE JOB YAML
  read -r id dryrun force args <<< "$@"

  # Get the list of slides that are eligible
  update_histo_match_manifest_specimen $id > /dev/null
  SVSLIST=$(get_specimen_manifest_slides $id)

  # Get a full directory dump for processed files
  FREMOTE=$(mktemp /tmp/preproc-remote-list.XXXXXX)
  gsutil ls "gs://mtl_histology/$id/histo_proc/**" > $FREMOTE || touch $FREMOTE

  # Append with the listing of raw files
  gsutil ls "gs://mtl_histology/$id/histo_raw/*" >> $FREMOTE

  # Check for existence of all remote files
  for svs in $SVSLIST; do

    # Check that the actual raw file exists
    if ! grep "gs://mtl_histology/$id/histo_raw/$svs\.\(tif\|svs\|tiff\)" $FREMOTE > /dev/null; then
      echo "Missing raw slide for $id $svs"
      continue
    fi

    BASE="gs://mtl_histology/$id/histo_proc/${svs}/preproc/${svs}_"

    # Check if we have to do this
    local must_run=0
    if [[ $force -gt 0 ]]; then
      must_run=1
    fi
    for fn in thumbnail.tiff x16.png resolution.txt metadata.json rgb_40um.nii.gz; do
      fn_full=${BASE}${fn}
      if ! grep "$fn_full" $FREMOTE > /dev/null; then
        must_run=1
      fi
    done

    if [[ $dryrun -gt 0 ]]; then
      if [[ $must_run -gt 0 ]]; then
        echo "Needs preprocessing: $id $svs"
      fi
    else
      if [[ $must_run -gt 0 ]]; then

        # Get a job ID
        JOB=$(echo $id $svs | md5sum | cut -c 1-6)

        # Create a yaml from the template
        YAML=/tmp/preproc_${JOB}.yaml
        cat $ROOT/scripts/yaml/histo_preproc.template.yaml | \
          sed -e "s/%ID%/${id}/g" -e "s/%JOBID%/$JOB/g" -e "s/%SVS%/${svs}/g" \
          > $YAML

        echo "Scheduling job $id $svs $YAML"
        kube apply -f $YAML
      else
        echo "Skipping: $id $svs"
      fi
    fi

  done
}

# Preprocesses histology slides via Kubernettes cluster. The optional mode
# parameter may have value 'force' to force reprocessing of all slices or
# 'dryrun' to just print what slides would be processed
function preprocess_slides_all()
{
  # Read the command-line options\
  local dryrun=0
  local force=0

  while getopts "DF" opt; do
    case $opt in
      D) dryrun=1;;
      F) force=1;;
      \?) echo "Unknown option $OPTARG"; exit 2;;
    esac
  done

  # Get remaining args
  shift $((OPTIND - 1))

  # Specimen regexp
  REGEXP=$1

  # Process the individual blocks
  while read -r id url; do
    if [[ $id =~ $REGEXP ]]; then
      preprocess_specimen_slides ${id} ${dryrun} ${force}
    fi
  done < "$MDIR/histo_matching.txt"
}

# Compute Tau density (or similar map) for all slides in a specimen
# Inputs are:
#   id (specimen id)
#   stain (Tau, NAB, etc)
#   model (e.g., tangles)
#   force (if set, clobber existing results)
function density_map_specimen()
{
  read -r id stain model dryrun force legacy args <<< "$@"

  # Get the list of slides that are eligible
  update_histo_match_manifest_specimen $id > /dev/null
  SVSLIST=$(get_specimen_manifest_slides $id $stain)

  # Get a full directory dump
  FREMOTE=$(mktemp /tmp/dmap-remote-list.XXXXXX)
  gsutil ls "gs://mtl_histology/$id/histo_proc/**" > $FREMOTE
  gsutil ls "gs://mtl_histology/$id/histo_raw/**" >> $FREMOTE

  # Check for existence of all remote files
  for svs in $SVSLIST; do

    # Define the outputs
    BASE="gs://mtl_histology/$id/histo_proc/${svs}"
    NII="${BASE}/density/${svs}_${stain}_${model}_densitymap.nii.gz"
    THUMB="${BASE}/preproc/${svs}_thumbnail.tiff"

    # Check that preprocessing has been run for this slide
    if ! grep "$THUMB" $FREMOTE > /dev/null; then
      echo "Slide ${svs} has not been preprocessed yet. Skipping"
      continue
    fi

    # Check if the result already exists
    if [[ ! $force || $force -eq 0 ]] && grep "$NII" $FREMOTE > /dev/null; then
      if [[ ! $dryrun -gt 0 ]]; then
        echo "Result already exists for slide ${svs}. Skipping"
      fi
      continue
    fi

    # If dryrun, just inform that we would process the slide
    if [[ $dryrun -gt 0 ]]; then
      echo "Needs density mapping:" $id $svs
      continue
    fi

    # Geberate a job ID and YAML file
    JOB=$(echo $id $svs $stain $model | md5sum | cut -c 1-6)
    YAML=/tmp/density_${JOB}.yaml

    # Legacy mode
    if [[ $legacy -gt 0 ]]; then

      # Do YAML substitution
      cat $ROOT/scripts/yaml/density_map_legacy.template.yaml | \
        sed -e "s/%ID%/${id}/g" -e "s/%JOBID%/${JOB}/g" -e "s/%SVS%/${svs}/g" \
            -e "s/%STAIN%/${stain}/g" -e "s/%MODEL%/${model}/g" \
        > $YAML

    else

      # Get the GS url of the raw slide
      SLIDE_URL=$(grep "gs://mtl_histology/$id/histo_raw/${svs}\.\(tif\|tiff\|svs\)" "$FREMOTE")

      # Get the GS url of the model
      MODEL_URL=$(jq -r ".${stain}.${model}.network" "$MDIR/density_param.json")

      # Get the downsampling factor
      DOWNSAMPLE=$(jq -r ".${stain}.${model}.downsample" "$MDIR/density_param.json")

      # Do YAML substitution
      cat $ROOT/scripts/yaml/density_map.template.yaml | \
        sed -e "s/%ID%/${id}/g" -e "s/%JOBID%/${JOB}/g" -e "s|%INPUT%|${SLIDE_URL}|g" \
            -e "s|%OUTPUT%|${NII}|g" -e "s|%NETWORK%|${MODEL_URL}|g" \
            -e "s/%DOWNSAMPLE%/${DOWNSAMPLE}/g" \
        > $YAML

    fi

    # Run the yaml
    echo "Scheduling job $id $svs $YAML"
    kube apply -f $YAML

  done
}

function density_map_all()
{
  # Read the command-line options\
  local dryrun=0
  local force=0
  local legacy=0

  while getopts "DFL" opt; do
    case $opt in
      D) dryrun=1;;
      F) force=1;;
      L) legacy=1;;
      \?) echo "Unknown option $OPTARG"; exit 2;;
    esac
  done

  # Get remaining args
  shift $((OPTIND - 1))

  # Specimen regexp
  stain=${1?}
  model=${2?}
  REGEXP=$3

  # Process the individual blocks
  while read -r id url; do
    if [[ $id =~ $REGEXP ]]; then
      density_map_specimen ${id} ${stain} ${model} ${dryrun} ${force}
    fi
  done < "$MDIR/histo_matching.txt"
}

function blockface_preprocess_specimen()
{
    read -r id args <<< "$@"

    JOB=$(echo $id | md5sum | cut -c 1-6)
    YAML=/tmp/blockface_${JOB}.yaml
    cat $ROOT/scripts/yaml/blockface_preproc.template.yaml | \
      sed -e "s/%ID%/${id}/g" -e "s/%JOBID%/${JOB}/g" > $YAML

    # Run the yaml
    echo "Scheduling job $ID $YAML"
    kube apply -f $YAML
}

function blockface_preprocess_all()
{
  for id in $(cat $MDIR/histo_matching.txt | awk '{print $1}'); do
    blockface_preprocess_specimen $id
  done
}


# Compute Tau density (or similar map) for all slides in a specimen
# Inputs are:
#   id (specimen id)
#   stain (Tau, NAB, etc)
#   model (e.g., tangles)
#   force (if set, clobber existing results)
function nissl_multichannel_specimen()
{
  read -r id dryrun force args <<< "$@"

  # Get the list of slides that are eligible
  update_histo_match_manifest_specimen $id > /dev/null
  SVSLIST=$(get_specimen_manifest_slides $id NISSL)

  # Get a full directory dump
  FREMOTE=$(mktemp /tmp/dmap-remote-list.XXXXXX)
  gsutil ls "gs://mtl_histology/$id/histo_proc/**" > $FREMOTE

  # Check for existence of all remote files
  for svs in $SVSLIST; do

    # Define the outputs
    BASE="gs://mtl_histology/$id/histo_proc/${svs}"
    NII="${BASE}/preproc/${svs}_deepcluster.nii.gz"
    THUMB="${BASE}/preproc/${svs}_thumbnail.tiff"

    # Check that preprocessing has been run for this slide
    if ! grep "$THUMB" $FREMOTE > /dev/null; then
      echo "Slide ${svs} has not been preprocessed yet. Skipping"
      continue
    fi

    # Check if the result already exists
    if [[ ! $force || $force -eq 0 ]] && grep "$NII" $FREMOTE > /dev/null; then
      if [[ ! $dryrun -gt 0 ]]; then
        echo "Result already exists for slide ${svs}. Skipping"
      fi
      continue
    fi

    # If dryrun, just inform that we would process the slide
    if [[ $dryrun -gt 0 ]]; then
      echo "Needs deepcluster mapping:" $id $svs
      continue
    fi

    # Geberate a job ID and YAML file
    JOB=$(echo $id $svs | md5sum | cut -c 1-6)
    YAML=/tmp/density_${JOB}.yaml

    # Do YAML substitution
    cat $ROOT/scripts/yaml/nissl_multichan.template.yaml | \
      sed -e "s/%ID%/${id}/g" -e "s/%JOBID%/${JOB}/g" -e "s/%SVS%/${svs}/g" \
      > $YAML

    # Run the yaml
    echo "Scheduling job $id $svs $YAML"
    kube apply -f $YAML

  done
}

function nissl_multichannel_all()
{
  # Read the command-line options\
  local dryrun=0
  local force=0

  while getopts "DF" opt; do
    case $opt in
      D) dryrun=1;;
      F) force=1;;
      \?) echo "Unknown option $OPTARG"; exit 2;;
    esac
  done

  # Get remaining args
  shift $((OPTIND - 1))

  # Specimen regexp
  REGEXP=$1

  # Process the individual blocks
  while read -r id url; do
    if [[ $id =~ $REGEXP ]]; then
      nissl_multichannel_specimen ${id} ${dryrun} ${force}
    fi
  done < "$MDIR/histo_matching.txt"
}

# Bring files from the cloud to local storage
function rsync_histo_proc()
{
  read -r id args <<< "$@"

  # Location of the histology data in the cloud
  local SPECIMEN_HISTO_GCP_ROOT="gs://mtl_histology/${id}/histo_proc"
  local SPECIMEN_HISTO_LOCAL_ROOT="$ROOT/input/${id}/histo_proc"

  # Create some exclusions
  local EXCL=".*_x16\.png|.*_x16_pyramid\.tiff|.*mrilike\.nii\.gz|.*tearfix\.nii\.gz|.*affine\.mat|.*densitymap\.tiff"
  mkdir -p "$SPECIMEN_HISTO_LOCAL_ROOT"
  gsutil -m rsync -R -x "$EXCL" "$SPECIMEN_HISTO_GCP_ROOT/" "$SPECIMEN_HISTO_LOCAL_ROOT/"
}

# Bring files from the cloud to local storage
function rsync_histo_all()
{
  REGEXP=$1
  cat $MDIR/histo_matching.txt | grep "$REGEXP" | while read -r id; do
    rsync_histo_proc $id
  done
}

# Generic function to download an SVG from PHAS with timestamp check
# usage:
#   download_svg <task_id> <svs> <wdir>
# environment variables:
#   SVG_CURL_OPTS: options to pass curl
function download_svg()
{
  local task_id svs WDIR TS_URL TS_REMOTE_JSON_COPY TS_REMOTE
  local LOCAL_SVG LOCAL_TIMESTAMP_JSON

  # Read the inputs
  read -r task_id svs WDIR <<< "$@"

  # Create directory
  mkdir -p $WDIR

  # Get the timestamp of the annotation
  TS_URL="$PHAS_SERVER/api/task/$task_id/slidename/$svs/annot/timestamp"
  TS_REMOTE_JSON_COPY=$TMPDIR/${svs}_remote_ts.json
  if ! curl_cat_url "$TS_URL" > $TS_REMOTE_JSON_COPY; then
    echo "Unable to download $TS_URL"
    return
  fi

  # Read the timestamp
  TS_REMOTE=$(jq .timestamp < $TS_REMOTE_JSON_COPY)

  # The different filenames that will be output by this function
  LOCAL_SVG=$WDIR/${svs}_annot.svg
  LOCAL_TIMESTAMP_JSON=$WDIR/${svs}_timestamp.json

  # If there is nothing on the server, clean up locally and stop
  if [[ $TS_REMOTE == "null" ]]; then
    rm -f $LOCAL_SVG $LOCAL_TIMESTAMP_JSON
    return
  fi

  # Does the SVG exist? Then check if it is current
  if [[ -f $LOCAL_SVG ]]; then
    local TS_LOCAL
    if [[ -f $LOCAL_TIMESTAMP_JSON ]]; then
      TS_LOCAL=$(cat $LOCAL_TIMESTAMP_JSON | jq .timestamp)
    else
      TS_LOCAL=0
    fi

    if [[ $(echo "$TS_REMOTE > $TS_LOCAL" | bc) -eq 1 ]]; then
      rm -f $LOCAL_SVG
    else
      echo "File $LOCAL_SVG is up to date"
    fi
  fi

  if [[ ! -f $LOCAL_SVG ]]; then
    # Download the SVG
    local SVG_URL="$PHAS_SERVER/api/task/$task_id/slidename/$svs/annot/svg"
    if ! curl_download_url "$SVG_URL" "$LOCAL_SVG" "$SVG_CURL_OPTS"; then
      echo "Unable to download $LOCAL_SVG"
      return
    fi

    # Record the timestamp
    cat $TS_REMOTE_JSON_COPY > $LOCAL_TIMESTAMP_JSON
  fi
}

# Get the slide annotations in SVG format from the server and place them in
# the input directory
function rsync_histo_annot()
{
  # What specimen and block are we doing this for?
  read -r id args <<< "$@"

  # Sync the histo evaluation files
  SVSLIST=$(get_specimen_manifest_slides $id)
  for svs in $SVSLIST; do
    # Get the registration evaluation annotations
    SVG_CURL_OPTS="-d strip_width=1000"
    download_svg $PHAS_REGEVAL_TASK $svs "$ROOT/input/$id/histo_regeval/"
  done

  # Sync the anatomical annotations
  SVSLIST=$(get_specimen_manifest_slides $id NISSL)

  # Read the slide manifest
  for svs in $SVSLIST; do
    # Download the SVG with appropriate settings
    SVG_CURL_OPTS="-d stroke_width=250 -d font_size=2000px -d font_color=darkgray"
    download_svg $PHAS_ANNOT_TASK $svs "$ROOT/input/$id/histo_annot/"
  done
}

function rsync_histo_annot_all()
{
  # Read an optional regular expression from command line
  REGEXP=$1

  # Process the individual blocks
  while read -r id blocks; do
    if [[ $id =~ $REGEXP ]]; then
      rsync_histo_annot $id
    fi
  done < "$MDIR/blockface_src.txt"

}


function blockface_multichannel_block()
{
  read -r id block force args <<< "$@"

  # Geberate a job ID and YAML file
  JOB=$(echo $id $block | md5sum | cut -c 1-6)
  YAML=/tmp/density_${JOB}.yaml

  # Do YAML substitution
  cat $ROOT/scripts/yaml/blockface_multichan.template.yaml | \
    sed -e "s/%ID%/${id}/g" -e "s/%JOBID%/${JOB}/g" -e "s/%BLOCK%/${block}/g" \
    > $YAML

  # Run the yaml
  echo "Scheduling job $id $block $YAML"
  kube apply -f $YAML
}

function blockface_multichannel_all()
{
  while read -r id blocks; do

    for b in $blocks; do

      blockface_multichannel_block $id $b

    done

  done < "$MDIR/blockface_src.txt"
}

# Bring files from the cloud to local storage
function rsync_bf_proc()
{
  read -r id args <<< "$@"

  # Location of the histology data in the cloud
  local SPECIMEN_BF_GCP_ROOT="gs://mtl_histology/${id}/bf_proc"
  local SPECIMEN_BF_LOCAL_ROOT="$ROOT/input/${id}/bf_proc"

  # Create some exclusions
  local EXCL=".*\.png|.*\.tiff"
  mkdir -p "$SPECIMEN_BF_LOCAL_ROOT"
  gsutil -m rsync -R -x "$EXCL" "$SPECIMEN_BF_GCP_ROOT/" "$SPECIMEN_BF_LOCAL_ROOT/"
}

function rsync_bf_proc_all()
{
  REGEXP=$1
  cat $MDIR/blockface_src.txt | grep "$REGEXP" | while read -r id; do
    rsync_bf_proc $id
  done
}


function usage()
{
  echo "recon.sh : Histology to MRI reconstruction script for R01-AG056014"
  echo "Usage:"
  echo "  recon.sh [options] <function> [args]"
  echo "Options:"
  echo "  -d                                          : Turn on command echoing (for debugging)"
  echo "Primary functions:"
  echo "  update_histo_match_manifest_all [regex]     : Update manifests for all/some specimens"
  echo "  preprocess_slides_all [-D] [-F] [regex]     : Run basic pre-processing on slides in GCP"
  echo "  check_for_new_slides_all [regex]            : Update online histology spreadsheet"
  echo "  density_map_all [-D] [-F] <stain> <model> [regex] "
  echo "                                              : Compute density maps with WildCat"
  echo "Common options:"
  echo "  -D                                          : Dry run: just show slides that need action"
  echo "  -F                                          : Force: override existing results"
}

# Read the command-line options
while getopts "dh" opt; do
  case $opt in
    d) set -x;;
    h) usage; exit 0;;
    \?) echo "Unknown option $OPTARG"; exit 2;;
    :) echo "Option $OPTARG requires an argument"; exit 2;;
  esac
done

# Get remaining args
shift $((OPTIND - 1))

# Reset OPTIND for functions
OPTIND=1

# No parameters? Show usage
if [[ "$#" -lt 1 ]]; then
  usage
  exit 255
fi

# Main entrypoint into script
COMMAND=$1
if [[ ! $COMMAND ]]; then
  main
else
  shift
  $COMMAND "$@"
fi
