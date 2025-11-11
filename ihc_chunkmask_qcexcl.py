#!/usr/bin/env python3
import pandas as pd
import os
import sys
import re
import SimpleITK as sitk
import numpy as np

# Read the manifest with pandas
d = pd.read_csv(sys.argv[1])

# Get the specimen information 
specimen = sys.argv[2]
block = re.sub(r'[A-Z]*([0-9])[ap]', r'\1', sys.argv[3])
section = sys.argv[4]

# Clean the columns
d.Block = d.Block.str.replace(r'[A-Z]*([0-9])[ap]', r'\1',regex=True)

# Find the match
m = d.query('Specimen == "{}" and Block == "{}" and Section == {}'.format(specimen, block, section)).Chunks

# Check the length of the match
labels = []
if m.shape[0] == 1:
    
    # Get the list of the chunks
    chunk = str(m.iloc[0]).strip()
    if chunk == 'all':
        labels = [ -1 ]
    else:
        chunk = re.sub(r'\D', r' ', chunk)
        labels = list(int(s) for s in chunk.split())

# Load the image
mask = sitk.ReadImage(sys.argv[5])
arr = np.around(sitk.GetArrayFromImage(mask)).astype(int)

# Apply the changes
vox_before = np.sum(arr > 0)
for l in labels:
    if l == -1:
        arr[:] = 0
    else:
        arr[arr == l] = 0
vox_after = np.sum(arr > 0)

# Binarize the mask
arr = np.where(arr > 0, 1, 0)

# Save the mask
mask_filtered = sitk.GetImageFromArray(arr, isVector=False)
mask_filtered.CopyInformation(mask)
sitk.WriteImage(mask_filtered, sys.argv[6])

# Print change in mask
print('Mask reduced from {} to {} pixels'.format(vox_before, vox_after))

    