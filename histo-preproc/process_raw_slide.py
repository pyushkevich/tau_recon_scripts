#!/usr/bin/env python
from __future__ import print_function
import openslide
import numpy as np
import os, time, math, sys
import getopt
import argparse
import pyvips
import SimpleITK as sitk
import json

# Little function to round numbers up to closest divisor of d
def round_up(x, d):
    return int(math.ceil(x * 1.0 / d) * d)

# This little function computes the means of image tiles. No smoothing is performed
def tile_means(img, tile_size):
    b=np.mean(img.reshape(img.shape[0],-1,tile_size),axis=2)
    c=np.mean(b.reshape(-1,tile_size,b.shape[1]),axis=1)
    return c

# Read spacing from an OpenSlide
# Get the image spacing from the header, in mm units
def get_spacing(slide):
    (sx, sy) = (0.0, 0.0)
    if all(['tiff.' + x in slide.properties 
            for x in ('XResolution','YResolution','ResolutionUnit')]):
        rx = float(slide.properties['tiff.XResolution'])
        ry = float(slide.properties['tiff.XResolution'])
        runit = slide.properties['tiff.ResolutionUnit']
        rbase = {'centimeter':10.0, 'millimeter':1.0}.get(runit,0.0)
        sx,sy = rbase / rx, rbase / ry
    elif 'openslide.mpp-x' in slide.properties:
        sx = float(slide.properties['openslide.mpp-x']) / 1000.0
        sy = float(slide.properties['openslide.mpp-y']) / 1000.0
    elif 'openslide.comment' in slide.properties:
        for z in slide.properties['openslide.comment'].split('\n'):
            r = parse.parse('Resolution = {} um', z)
            if r is not None:
                sx = float(r[0]) / 1000.0
                sy = float(r[0]) / 1000.0
    # If there is no spacing, throw exception
    if sx == 0.0 or sy == 0.0:
        raise Exception('No spacing information in image')
    return (sx, sy)


# Main
def main(argv):

    # Create an argument parser
    parser = argparse.ArgumentParser()
    parser.add_argument('-i', '--input', type=str,
                        help='Input SVS or TIFF file')
    parser.add_argument('-s', '--summary', type=str, 
                        help='Filename prefix for summary outputs')
    parser.add_argument('-m', '--x16', action='store_true',
                        help='Include x16 outputs in the summary')
    parser.add_argument('-l', '--check-levels', action='store_true',
                        help='Print the number of levels in the input image')
    args = parser.parse_args()

    # If only asking to see the number of levels, do that
    if args.check_levels:
        try:
            slide=openslide.OpenSlide(args.input)
            print(slide.level_count)
        except:
            print(-1)
        return
    elif not args.summary:
        print('Missing required argument: -s')
        return 255

    # Read the slide first
    slide=openslide.OpenSlide(args.input)

    # The simple thumbnail
    img = slide.get_thumbnail((1000,1000))
    img.save(args.summary + '_thumbnail.tiff')

    # The NIFTI thumbnail with fixed resolution
    (sx,sy) = get_spacing(slide)

    # Determine the dimensions of the thumbnail to achieve desired
    # resolution of 0.04x0.04mm
    wx = round_up(slide.dimensions[0] * sx / 0.04, 1)
    wy = round_up(slide.dimensions[1] * sy / 0.04, 1)

    # Get the thumbnail from the image at this resolution
    idata = np.asarray(slide.get_thumbnail((wx, wy)))
    (wwx, wwy) = (idata.shape[1], idata.shape[0])

    # Recompute the spacing using the actual size of image
    ssx = (sx * slide.dimensions[0]) / wwx
    ssy = (sy * slide.dimensions[1]) / wwy

    # Save as a NIFTI
    res = sitk.GetImageFromArray(idata, True)
    res.SetSpacing((ssx, ssy))
    sitk.WriteImage(res, args.summary + '_rgb_40um.nii.gz')

    # Save dimensions info to a JSON file
    with open(args.summary + "_metadata.json", "wt") as fp:
        json.dump({
            "dimensions": slide.dimensions,
            "level_count": slide.level_count,
            "level_dimensions": slide.level_dimensions,
            "level_downsamples": slide.level_downsamples,
            "spacing": (sx,sy) }, fp);

    # Get the label
    if 'label' in slide.associated_images:
        img = slide.associated_images['label']
        img.save(args.summary + '_label.tiff')

    # Get the label
    if 'macro' in slide.associated_images:
        img = slide.associated_images['macro']
        img.save(args.summary + '_macro.tiff')

    if args.x16:

        # Requested x16 middle-resolution image. The middle resolution images
        # can be generated using openslide very easily
        best_lev = 0
        for lev in range(slide.level_count):
          dsam=int(slide.level_downsamples[lev] + 0.5)
          if dsam <= 16:
            best_lev = lev

        # Downsample at this level
        image=slide.read_region((0,0), best_lev, slide.level_dimensions[best_lev])
        image.save(args.summary + '_x16.png')
        arr=np.array(image)

        # Create a pyvips image
        h,w,b = arr.shape
        ivips = pyvips.Image.new_from_memory(arr.reshape(h*w*b).data,w,h,b,'uchar')
        ivips.write_to_file(args.summary + '_x16_pyramid.tiff',
                            Q=80, tile=True, compression='jpeg', 
                            pyramid=True, bigtiff=True)


if __name__ == "__main__":
    main(sys.argv[1:])
