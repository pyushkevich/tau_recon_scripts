import argparse
import pandas as pd
import SimpleITK as sitk
import glob
import os
import numpy as np
import json
from phas.client.api import Client, SamplingROITask, Slide
from phas.dltrain import spatial_transform_roi, draw_sampling_roi, compute_sampling_roi_bounding_box
from picsl_greedy import Greedy2D
from PIL import Image

def map_sampling_roi(task_id, specimen, block, stain, section):
    
    # Create client and task
    client = Client('https://histo.itksnap.org', '/home/pauly2/.private/histo_itksnap_org_api_key.json')
    task = SamplingROITask(client, task_id)
    
    # Get a listing of slides for the task
    manifest = pd.DataFrame(task.slide_manifest(specimen=specimen)).set_index('id')
    df_nissl = manifest.query(f'specimen_private=="{specimen}" and block_name=="{block}" and section=={section} and stain=="NISSL"')
    df_ihc = manifest.query(f'specimen_private=="{specimen}" and block_name=="{block}" and section=={section} and stain=="{stain}"')
    if len(df_nissl) != 1 or len(df_ihc) != 1:
        raise ValueError('Wrong number of nissl or ihc sections found')
    
    slide_id_nissl, slide_id_ihc = df_nissl.index[0], df_ihc.index[0]
    slide_nissl = Slide(task, slide_id_nissl)
    slide_ihc = Slide(task, slide_id_ihc)
    slide_ihc.thumbnail_nifti_image(filename='../tmp/test_ihc_image.nii.gz')
    
    # Download the sampling ROIs for this slide
    sroi = task.slide_sampling_rois(slide_id_nissl)
    
    # Load the spatial transforms
    fglob = glob.glob(f'../work/{specimen}/ihc_reg/{block}/reg_{stain}_to_NISSL/slides/{specimen}_{block}_{section:02d}_*_{stain}')
    if len(fglob) != 1:
        raise ValueError('ihc_reg folder not found')
    folder = fglob[0]
    basename = os.path.basename(folder)
    warp = sitk.ReadImage(f'{folder}/{basename}_to_nissl_chunking_warp.nii.gz')
    rigid = np.loadtxt(f'{folder}/{basename}_to_nissl_global_rigid.mat')
    
    # Define a function that warps ROIs to new locations
    def my_transform(pos):
        p_fullres = np.array(pos)
        p_phys = (p_fullres + 0.5) * slide_nissl.spacing
        v = warp.EvaluateAtPhysicalPoint(p_phys)
        p_phys_warp = p_phys + v
        p_fullres_warp = p_phys_warp / slide_ihc.spacing - 0.5
        return p_fullres_warp[0], p_fullres_warp[1]
    
    # A couple of canvases
    canvas_nissl = Image.new('L', warp.GetSize())
    sx_nissl,sy_nissl = canvas_nissl.size[0] / slide_nissl.dimensions[0], canvas_nissl.size[1] / slide_nissl.dimensions[1]
    
    img_ihc = sitk.ReadImage('../tmp/test_ihc_image.nii.gz')
    canvas_ihc = Image.new('L', img_ihc.GetSize()[:2])
    sx_ihc,sy_ihc = canvas_ihc.size[0] / slide_ihc.dimensions[0], canvas_ihc.size[1] / slide_ihc.dimensions[1]
        
    # Apply the transform to the ROIs
    task.delete_sampling_rois_on_slide(slide_id_ihc)
    for r in sroi:
        geom = json.loads(r['json'])
        draw_sampling_roi(canvas_nissl, geom, sx_nissl,sy_nissl, fill=255)
        geom_warped = spatial_transform_roi(geom, my_transform)
        roi_id = task.create_sampling_roi(slide_id_ihc, r['label'], geom_warped)
        draw_sampling_roi(canvas_ihc, geom_warped, sx_ihc,sy_ihc, fill=255)
        
        bbox = compute_sampling_roi_bounding_box(geom_warped)
        patch = slide_ihc.get_patch(
            ((bbox[0] + bbox[2])//2, (bbox[1] + bbox[3])//2), 0, (512,512))
        patch.save(f'../tmp/test_patch_{roi_id}.png')        
        
    pix = np.array(canvas_nissl, dtype=np.uint8)
    seg_nissl = sitk.GetImageFromArray(pix)
    seg_nissl.CopyInformation(warp)
    sitk.WriteImage(seg_nissl, '../tmp/test_seg_nissl.nii.gz')

    pix = np.array(canvas_ihc, dtype=np.uint8)
    seg_ihc = sitk.GetImageFromArray(pix[None,:,:])
    seg_ihc.CopyInformation(img_ihc)
    sitk.WriteImage(seg_ihc, '../tmp/test_seg_ihc.nii.gz')
    

if __name__ == '__main__':
    parse = argparse.ArgumentParser(description="Map sampling ROI from NISSL to another stain")
    parse.add_argument('--task', type=int)
    parse.add_argument('--specimen', type=str)
    parse.add_argument('--block', type=str)
    parse.add_argument('--stain', type=str)
    parse.add_argument('--section', type=int)
    args = parse.parse_args()
    map_sampling_roi(args.task, args.specimen, args.block, args.stain, args.section)