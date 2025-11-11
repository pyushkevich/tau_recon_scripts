# Managing Cloud-Based Histology Tasks

The script `svs_to_cloud.sh` is used to manage histology tasks. Most commands take a regular expression, for example `HNL-33` or `HNL-33|HNL-35`, to restrict processing to specific specimens.

```sh
Usage:
  recon.sh [options] <function> [args]
Options:
  -d                                          : Turn on command echoing (for debugging)
Primary functions:
  check_for_new_slides_all [regex]            : Update online histology spreadsheet
  update_histo_match_manifest_all [regex]     : Update manifests for all/some specimens
  preprocess_slides_all [-D] [-F] [regex]     : Run basic pre-processing on slides in GCP
  nissl_multichannel_all [-D] [-F] [regex]    : Run DeepCluster on NISSL slides in GCP
  density_map_all [-L] [-D] [-F] <stain> <model> [regex]
                                              : Compute density maps with WildCat
  rsync_histo_all [regex]                     : Download remote processing results
  rsync_histo_annot_all [regex]               : Download remote annotations
Blockface functions:
  blockface_preprocess_all [regex]            : Run basic preprocessing on BF images in GCP
  blockface_multichannel_all [regex]          : Run feature extraction on BF images in GCP
  rsync_bf_proc_all [regex]                   : Download remote BF processing results
Common options:
  -D                                          : Dry run: just show slides that need action
  -F                                          : Force: override existing results
  -L                                          : Use legacy code
```

## Checking for New Scanned Slides (`check_for_new_slides_all`)

This command will generate listings that can be pasted into the Google drive spreadsheet (`HistologyMatching`). This is necessary for the slides to be added to `histo.itksnap.org` and for slides to be processed using scripts in this repository.

Just run
```sh
./svs_to_cloud.sh check_for_new_slides_all <regex>
```

This will create a folder in `$ROOT/tmp/manifest/new_slides_for_histology_matching` that contains `.csv` files with data to paste into each tab of the spreadsheet. 

After running command, open HistologyMatching spreadsheet in GDrive

* Locate correct tab for the specimen (or create new one)
* Paste rows at the bottom of the sheet
* Data->split text to columns
* Clean up any issues with naming
* Add tags if necessary (e.g., diag for diagnostic slides), mark any slides that are duplicates as such
* Make sure column I (Diff) is extended to the new rows (this column is used to quickly see if there are slides out of sequence)
* Run the SortSlides macro under extensions

The command will also create file `new_specimens.csv` in `$ROOT/tmp/manifest/new_slides_for_histology_matching`. If you want subsequent commands to be available for these specimens, add them to `$ROOT/manifest/histology_matching.txt`. 

## Updating Histology Manifest Files (`update_histo_match_manifest_all`)

This will update the local manifest files in `$ROOT/input/histo_manifest/` folders. These files are essentially a mirror of the Google Spreadsheet `HistologyMatching`. 

```sh
./svs_to_cloud.sh check_for_new_slides_all <regex>
```

## Preprocessing Histology Slides (`preprocess_slides_all`)

This will run the basic preprocessing script in GCP. This **should not be necessary** for newer slides because the preprocessing is already done when the slides are scanned. 

If you want to run the script anyway, run the command below, use -D for dry run

```sh
bash ./svs_to_cloud.sh preprocess_slides_all [-D] [REGEX]
```
This will launch a bunch of cloud-based processing jobs. You can see the status of these jobs using `kubectl get jobs` and `kubectl get pods` commands.

## Running WildCat in GCP (`density_map_all`)

To apply a wildcat classifier to all the histology slides in Google Cloud, we run this command. It is recommended to first run this with the `-D` (dry run) flag. 

```sh
./svs_to_cloud.sh density_map_all [-L] [-D] [-F] <stain> <model> [regex]
```

**IMPORTANT**: Tau density maps are generated using legacy wildcat models (I think). Need to check which is the right one to run for tau models. Check and edit this documentation before proceeding to any Tau series.

Before running, we must ensure that the wildcat models exist. The models are configured in the file `$ROOT/manifest/density_param.json`. Below is an excerpt from the file:

```json
[
  "PV" : {
    "models": {
      "core": {
        "network": "gs://svsbucket/cnn_models/pv/core/exp01",
        "downsample": 16,
        "contrasts": {
          "core": {
            "weights": [ 0.0, 1.0 ],
            "softmax": 0
          }
        }
      }
    },
    "smoothing": "0.05x0.05x0.8mm"
  }
]
```

Here `PV` is the stain, and `core` is the model for that stain (this model is trained to extract interneuron cores), and `network` is the GCP location of the trained model.  

For example, to do a dry run with the PV scan, run

```sh
./svs_to_cloud.sh density_map_all -D PV core HNL-33
```

This will generate `.yaml` files in the temp directory that can be launched individually using `kubectl`. It is a good idea to run one of these commands to make sure it completes before scheduling the whole batch. For example:

```sh
kubectl apply -f /tmp/density_43ac6c.yaml
```

You should see output `job.batch/hist-torch-job-43ac6c created` after running the command. 

You can monitor the job with the commands below:
```sh
# Get job status
kubectl get jobs hist-torch-job-43ac6c

# Get status of the pod created for the job
get pods -l job-name=hist-torch-job-43ac6c

# Get logs from the pod (once container has been created)
kubectl logs -l job-name=hist-torch-job-43ac6c
```

Once you are sure that everything looks good, run the command for all slides, without the `-D` flag:

```sh
./svs_to_cloud.sh density_map_all PV core HNL-33
```


## Troubleshooting:

For issues running jobs on the GCP kubernetes cluster:

* If kubectl complains, run:

        gcloud container clusters get-credentials

* You may need to upgrade your cluster



