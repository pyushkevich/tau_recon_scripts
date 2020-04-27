import os
import numpy as np
import nibabel as nib
import matplotlib.pyplot as plt
from skimage import measure
import skimage.filters as flt
import skimage.morphology as morph
import scipy.interpolate as interp
import similaritymeasures as sim
import scipy.spatial.distance as sdist
import scipy.stats
import json
import sys

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

if __name__ == "__main__":

    if len(sys.argv) < 3:
        print("Wrong number of arguments")
        sys.exit(-1)

    # Load the data
    nii_mri = nib.load(sys.argv[1]);
    nii_hist = nib.load(sys.argv[2]);
    mri= np.array(nii_mri.dataobj).squeeze()
    hist = np.array(nii_hist.dataobj).squeeze()

    # Extract contours from histology
    h_mask = morph.binary_erosion(hist > 20, morph.disk(2))
    h_cnt = measure.find_contours(hist, 60, mask=h_mask);
    if len(h_cnt) < 1:
        eprint("No contours in histology: %d" % (len(h_cnt),))
        sys.exit(-1)

    # Find the longest contour (this is weak)
    h_idx = list(map(len, h_cnt)).index(max(list(map(len, h_cnt))))

    # Finf the MRI cutoff
    m_flat = mri.flatten()
    m_thresh = scipy.stats.mode(m_flat[np.logical_and(m_flat > 0, m_flat < 5)]).mode[0]

    # Extract contours from MRI
    m_mask = morph.binary_erosion(mri < 4.5, morph.disk(5))
    m_cnt = measure.find_contours(mri, m_thresh / 2, mask=m_mask);
    if len(m_cnt) < 1:
        eprint("No contours in MRI: %d" % (len(m_cnt),))
        sys.exit(-1)

    # Find the longest contour (this is weak)
    m_idx = list(map(len, m_cnt)).index(max(list(map(len, m_cnt))))

    # Get the first part of each contour (assume there is only one)
    Xh,Xm=h_cnt[h_idx], m_cnt[m_idx]

    # Remap the contours to mm. 
    Ym=nii_mri.affine[:2, :2].dot(Xm.transpose()).transpose()+nii_mri.affine[:2, 3]
    Yh=nii_hist.affine[:2, :2].dot(Xh.transpose()).transpose()+nii_hist.affine[:2, 3]

    # Compute pointwise distance matrix
    D=sdist.cdist(Ym,Yh)
    d1,d2 = np.amin(D,0), np.amin(D,1)

    # Compute some standard metrics
    mtx = {
        "bde_median": np.mean((np.median(d1), np.median(d2))),
        "bde_mad": np.mean((np.mean(d1), np.mean(d2))),
        "bde_rms": np.sqrt(np.mean((np.mean(d1**2), np.mean(d2**2)))),
        "bde_hd95": np.mean((np.quantile(d1, 0.95), np.quantile(d2, 0.95))),
        "bde_hd": np.max((np.max(d1), np.max(d2))),
        "frechet" : sim.frechet_dist(Ym, Yh)
    }

    # Print the json
    print(json.dumps(mtx))
    sys.exit(0)







