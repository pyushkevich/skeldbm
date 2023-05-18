#!/usr/bin/env python3
import SimpleITK as sitk
import numpy as np
import argparse
import sys

def image_center_ras(img):
    pos = tuple(map(lambda x : x // 2, img.GetSize()))
    x = img.TransformIndexToPhysicalPoint(pos)
    return np.array((-x[0], -x[1]) + x[2:])


# Create a parser
parse = argparse.ArgumentParser(
    description="Surface mesh graph partitioning")

# Add the arguments
parse.add_argument('fixed', metavar='fixed', type=str, help='Fixed image')
parse.add_argument('moving', metavar='moving', type=str, help='Moving image')
args = parse.parse_args()

# Read the fixed image
fix = sitk.ReadImage(args.fixed)
mov = sitk.ReadImage(args.moving)

# Get the offset in RAS coordinates
offset = image_center_ras(mov) - image_center_ras(fix)

# Get the voxel dimensions
spc = np.array(fix.GetSpacing())

# Get the translation in whole voxel units
offset_voxel = offset - np.fmod(offset, spc)

# Create a c3d transform
tform = np.eye(4)
tform[0:3,3] = offset_voxel
np.savetxt(sys.stdout.buffer, tform, fmt='%f')
