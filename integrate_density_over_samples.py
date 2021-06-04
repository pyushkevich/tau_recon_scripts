# Import some libraries
import numpy as np
import pandas as pd
import argparse
import os
import json
import nibabel as nib
from scipy import signal

# Create a parser
parse = argparse.ArgumentParser(
    description="Integrate inclusion density over HistoAnnot samples")

# Add the arguments
parse.add_argument('manifest', metavar='manifest', type=str,
                   help="""
                        sample manifest file, generated on HistoAnnot server using command
                        flask samples-export-csv <task> manifest.csv --ids --specimen --header
                        """)
parse.add_argument('datadir', metavar='datadir', type=str,
                   help='Directory containing density files')

parse.add_argument('result', metavar='result', type=str,
                   help='Output CSV file')

parse.add_argument('--stain', metavar='stain', type=str, default='Tau',
                   help="Name of the stain analyzed")

parse.add_argument('--model', metavar='model', type=str, default='tangles',
                   help="Name of the CNN model analyzed")

parse.add_argument('--mean-filter-size', metavar='N', type=int, default=512,
                   help="Size of the mean filter, in raw histology image pixels")

# Parse the arguments
args = parse.parse_args()

# Parse the CSV file
df = pd.read_csv(args.manifest)

# Keep track of current nifti image and current slide
curr_slide, curr_nii, curr_bm, curr_mf = None, None, None, None

# Output dictionary
res = {
    'id': [],
    'specimen': [],
    'block': [],
    'slide_name': [],
    'label': [],
    'mean_burden': [],
    'max_sliding_burden': []
}

# Iterate over all samples
for index, row in df.iterrows():

    # Check the stain
    if row['stain'] != args.stain:
        continue

    # Find the json descriptor
    fn_json=os.path.join(args.datadir, '%s/histo_proc/%s/preproc/%s_metadata.json' %
                         (row['specimen_name'], row['slide_name'], row['slide_name']))

    # Find the nifti file
    fn_nii=os.path.join(args.datadir, '%s/histo_proc/%s/density/%s_%s_%s_densitymap.nii.gz' %
                         (row['specimen_name'], row['slide_name'], row['slide_name'],
                          args.stain, args.model))

    if not os.path.isfile(fn_json):
        print('Missing file ', fn_json)
        continue

    if not os.path.isfile(fn_nii):
        print('Missing file ', fn_nii)
        continue

    # Load the json file
    with open(fn_json,'rt') as f_json:
        metadata = json.load(f_json)

        # Load the nifti file
        if curr_slide != row['slide_name']:
            # Load slide
            curr_slide = row['slide_name']
            curr_nii = nib.load(fn_nii)

            # Compute burden map
            curr_bm = curr_nii.get_fdata()[:,:,0,0,1] - curr_nii.get_fdata()[:,:,0,0,0]
            curr_bm[curr_bm < 0.0] = 0.0
            curr_mf = None

        # The the index and size of current sample
        sx = curr_nii.shape[0] * 1.0 / metadata['dimensions'][0]
        sy = curr_nii.shape[1] * 1.0 / metadata['dimensions'][1]

        # Get the nifti dimensions and scaling factor
        nx, ny = int(sx * row['x'] + 0.5), int(sy * row['y'] + 0.5)
        nw, nh = int(sx * row['w'] + 0.5), int(sy * row['h'] + 0.5)

        # Extract the relevant chunk
        roi = curr_bm[nx:nx+nw,ny:ny+nh]

        # Calculate the mean burden
        burden=np.mean(roi)

        # Calculate the max sliding window burden
        fx, fy = int(sx * args.mean_filter_size + 0.5), int(sy * args.mean_filter_size + 0.5)
        kernel = np.full((fx, fy), 1.0 / (fx * fy))
        max_sliding=np.amax(
            signal.convolve(roi, kernel, mode='same') / signal.convolve(np.ones(roi.shape), kernel, mode='same'))

        # Print details in a report
        res['id'].append(row['id'])
        res['specimen'].append(row['specimen_name'])
        res['block'].append(row['block_name'])
        res['slide_name'].append(row['slide_name'])
        res['label'].append(row['label_name'])
        res['mean_burden'].append(burden)
        res['max_sliding_burden'].append(max_sliding)

        print('%s\t%s\t%d,%d,%d,%d\t%6.4f\t%6.4f' %
              (row['slide_name'], row['label_name'], nx, ny, nw, nh, burden, max_sliding))

# Export the dataframe as CSV
pd.DataFrame(res).to_csv(args.result)


