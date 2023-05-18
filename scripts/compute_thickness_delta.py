import argparse
import vtk
import numpy as np
from vtk.util import numpy_support


# Read VTK mesh, clean, triangulate, and extract vertices and connectivity matrix
def vtk_load_tetmesh(filename):
    reader = vtk.vtkUnstructuredGridReader()
    reader.SetFileName(filename)
    reader.Update()
    return reader.GetOutput()


# Write VTK mesh
def vtk_save_tetmesh(mesh, filename):
    writer = vtk.vtkUnstructuredGridWriter()
    writer.SetInputData(mesh)
    writer.SetFileName(filename)
    writer.SetFileVersion(42)
    writer.Update()


def tetra_volume(T):
    Tnorm = T[0:3,:] - T[3,:]
    return np.abs(np.dot(Tnorm[0,:], np.cross(Tnorm[1,:], Tnorm[2,:])) / 6.0)


def tetra_edgelen(T, v1, v2):
    edge = T[v1,:] - T[v2,:]
    return np.sqrt(np.dot(edge, edge)) 


def tetra_circumradius(T):
    a,b,c = tetra_edgelen(T,0,1), tetra_edgelen(T,0,2), tetra_edgelen(T,0,3)
    A,B,C = tetra_edgelen(T,2,3), tetra_edgelen(T,1,3), tetra_edgelen(T,1,2)
    V = tetra_volume(T)
    R = np.sqrt((a*A+b*B+c*C)*(-a*A+b*B+c*C)*(a*A-b*B+c*C)*(a*A+b*B-c*C)) / (24*V)
    return R


def tetmesh_stats(x, y):
    vol = np.zeros(len(y))
    rad = np.zeros(len(y))
    for i,v in enumerate(y):
        T = x[v]
        vol[i] = tetra_volume(T)
        rad[i] = tetra_circumradius(T)
    return vol, rad


# Append a cell array to a VTK mesh
def tetmesh_append_array(mesh, array, name):
    va = vtk.util.numpy_support.numpy_to_vtk(array)
    va.SetName(name)
    mesh.GetCellData().AddArray(va)


# Create a parser
parse = argparse.ArgumentParser(
    description="Surface mesh graph partitioning")

# Add the arguments
parse.add_argument('baseline', metavar='baseline', type=str, help='baseline mesh (VTK-readable format)')
parse.add_argument('followup', metavar='followup', type=str, help='followup mesh (VTK-readable format)')
parse.add_argument('result', metavar='result', type=str, help='Delta result mesh')
parse.add_argument('-e', '--expid', metavar='expid', type=str, help='Experiment ID (prefixed to output arrays)')

# Do the parsing
args = parse.parse_args()

# Load the meshes
bl = vtk_load_tetmesh(args.baseline)
fu = vtk_load_tetmesh(args.followup)

# Get the tetrahedron index matrix
y = vtk.util.numpy_support.vtk_to_numpy(bl.GetCells().GetData())
y = y.reshape(-1,5)[:,1:]

# Get the point coordinates
x_bl = vtk.util.numpy_support.vtk_to_numpy(bl.GetPoints().GetData())
x_fu = vtk.util.numpy_support.vtk_to_numpy(fu.GetPoints().GetData())

# Compute the excribed sphere radii 
v_bl, r_bl = tetmesh_stats(x_bl, y)
v_fu, r_fu = tetmesh_stats(x_fu, y)

# Prefix for output arrays
prefix = (args.expid + '_') if args.expid is not None else ''

# Append the arrays
tetmesh_append_array(bl, r_bl, prefix + "r_bl")
tetmesh_append_array(bl, r_fu, prefix + "r_fu")
tetmesh_append_array(bl, (r_bl - r_fu) / r_bl, prefix + "r_atrophy")
tetmesh_append_array(bl, v_bl, prefix + "v_bl")
tetmesh_append_array(bl, v_fu, prefix + "v_fu")
tetmesh_append_array(bl, (v_bl - v_fu) / v_bl, prefix + "v_atrophy")

# Save the mesh
vtk_save_tetmesh(bl, args.result)
