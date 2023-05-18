#!/usr/bin/env python3
import vtk
import SimpleITK as sitk
from vtk.util.numpy_support import vtk_to_numpy
import numpy as np
import argparse

# Create a parser
parse = argparse.ArgumentParser(
    description="Combine ROI atrophy rates for TJR experiments")

# Add the arguments
parse.add_argument('-m','--tetra_fix', type=str, help='path to fixseg_gm_mesh_tetra.vtk', required=True)
parse.add_argument('-j','--tetra_trj', type=str, help='path to fixseg_gm_mesh_tetra_hw_tjr_jacobian_xyz.vtk', required=True)
parse.add_argument('-s','--seg', type=str, help='Path to fixed ASHS segmentation', required=True)
parse.add_argument('-i','--id', type=str, help='Subject ID to print', required=True)

# Do the parsing
args = parse.parse_args()

# Read the tetrahedral mesh in space of the segmentation
reader = vtk.vtkUnstructuredGridReader()
reader.SetFileName(args.tetra_fix)
reader.Update()
seg_mesh = reader.GetOutput()

# Extract the centers of the Voronoi tetrahedra
tet_ctr = vtk_to_numpy(seg_mesh.GetCellData().GetArray('VoronoiCenter'))

# Read the mesh with Jacobians
reader = vtk.vtkUnstructuredGridReader()
reader.SetFileName(args.tetra_trj)
reader.Update()
jac_mesh = reader.GetOutput()

# Compute mesh volumes
q = vtk.vtkMeshQuality()
q.SetInputData(jac_mesh)
q.SetTetQualityMeasureToVolume()
q.Update()
jac_mesh_vol = q.GetUnstructuredGridOutput()
vol_bl = np.abs(vtk_to_numpy(jac_mesh_vol.GetCellData().GetScalars()))

# Extract the Jacobian
jac = vtk_to_numpy(jac_mesh_vol.GetCellData().GetArray('jacobian'))

# Read the segmentation image
iseg = sitk.ReadImage(args.seg)

# Compute the voxel coordinates
tet_ctr_vox = np.zeros_like(tet_ctr)
ras_to_lps = np.diag([-1, -1, 1])
for i in range(tet_ctr.shape[0]):
    tet_ctr_vox[i,:] = iseg.TransformPhysicalPointToContinuousIndex(ras_to_lps @ tet_ctr[i,:])

# For each label, assign each tetrahedron a weight
label_tet_wgt = {}
for label in 1,2,10,11,12,13:
    img_t = sitk.BinaryThreshold(iseg, label, label, 1, 0)
    label_tet_wgt[label] = np.zeros(tet_ctr.shape[0])
    for i in range(tet_ctr.shape[0]):
        label_tet_wgt[label][i] = img_t.EvaluateAtContinuousIndex(tet_ctr_vox[i,:])
        
    label_vol_bl = np.sum(vol_bl * label_tet_wgt[label])
    label_vol_fu = np.sum(vol_bl * jac * label_tet_wgt[label])
    print("{},{},{},{}".format(args.id, label, label_vol_bl, label_vol_fu))
