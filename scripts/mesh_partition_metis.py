import argparse
from enum import Flag
import metis
import vtk
import numpy as np
from vtk.util import numpy_support
import pymeshlab

# Read VTK mesh, clean, triangulate, and extract vertices and connectivity matrix
def vtk_load_mesh(filename):
    reader = vtk.vtkPolyDataReader()
    reader.SetFileName(filename)
    reader.Update()
    
    clean = vtk.vtkCleanPolyData()
    clean.SetInputConnection(reader.GetOutputPort())

    tri = vtk.vtkTriangleFilter()
    tri.SetInputConnection(clean.GetOutputPort())
    tri.Update()
    return tri.GetOutput()


# Write VTK mesh
def vtk_save_mesh(pd, filename):
    writer = vtk.vtkPolyDataWriter()
    writer.SetInputData(pd)
    writer.SetFileName(filename)
    writer.SetFileVersion(42)
    writer.Update()


# Extract vertex and triangle arrays from a polydata
def vtk_trimesh_get_arrays(pd):
    # Get the points array
    x = vtk.util.numpy_support.vtk_to_numpy(pd.GetPoints().GetData())
    y = vtk.util.numpy_support.vtk_to_numpy(pd.GetPolys().GetData())
    y = y.reshape(-1,4)[:,1:]
    return x,y


# Append a cell array to a VTK mesh
def vtk_polydata_append_array(pd, array, name):
    va = vtk.util.numpy_support.numpy_to_vtk(array)
    va.SetName(name)
    pd.GetCellData().AddArray(va)


def vtk_polydata_set_points(pd, array):
    va = vtk.util.numpy_support.numpy_to_vtk(array)
    pd.GetPoints().SetData(va)


# Get a face adjacency list
def trimesh_face_adjacency(tri):
    # First pass - associate each edge with triangles
    edges = {}
    for i,t in enumerate(tri):
        for e in (t[0],t[1]), (t[1], t[2]), (t[2], t[0]):
            e_sort = (min(e[0],e[1]), max(e[0],e[1]))
            if e_sort not in edges:
                edges[e_sort] = set([i])
            else:
                edges[e_sort].add(i)

    # Second pass - find all neighbors of a triangle
    nbr = list()
    for i,t in enumerate(tri):
        nbr_i = set([])
        for e in (t[0],t[1]), (t[1], t[2]), (t[2], t[0]):
            e_sort = (min(e[0],e[1]), max(e[0],e[1]))
            nbr_i = nbr_i.union(edges[e_sort].difference(set([i])))
        nbr.append(tuple(nbr_i))
    
    return nbr


# Create a parser
parse = argparse.ArgumentParser(
    description="Surface mesh graph partitioning")

# Add the arguments
parse.add_argument('source', metavar='source', type=str, help='input mesh (VTK-readable format)')
parse.add_argument('result', metavar='result', type=str, help='output partitioned mesh')
parse.add_argument('-n', type=int, help='Number of partitioning regions', default=80, dest='n_regions')
parse.add_argument('-s', type=int, help='Iterations of Taubin smoothing', default=0, dest='taubin_smooth')
parse.add_argument('-l', type=float, help='Taubin lambda parameter', default=0.6, dest='taubin_lambda')
parse.add_argument('-m', type=float, help='Taubin mu parameter', default=-0.4, dest='taubin_mu')
parse.add_argument('-r', action="store_true", help='Randomly shuffle region labels', default=-0.4, dest='shuffle')

# Do the parsing
args = parse.parse_args()

# Read the input mesh using VTK
pd = vtk_load_mesh(args.source)
va,fa = vtk_trimesh_get_arrays(pd)

# Perform some Taubin smoothing
if args.taubin_smooth > 0:
    ms = pymeshlab.MeshSet()
    ms.add_mesh(pymeshlab.Mesh(vertex_matrix = va, face_matrix = fa))
    ms.taubin_smooth(lambda_=args.taubin_lambda, mu=args.taubin_mu, stepsmoothnum=args.taubin_smooth)
    va = ms.current_mesh().vertex_matrix()

if args.n_regions > 0:

    # Compute face areas
    ms = pymeshlab.MeshSet()
    ms.add_mesh(pymeshlab.Mesh(vertex_matrix = va, face_matrix = fa))
    ms.per_face_quality_according_to_triangle_shape_and_aspect_ratio(metric='Area')
    area = ms.current_mesh().face_quality_array()

    # Process with METIS
    adj = trimesh_face_adjacency(fa)
    (objval, parts) = metis.part_graph(adj, nparts=args.n_regions, 
                                    nodew=list(map(lambda x: [int(10000 * x)], area)))

    # Relabel parts randomly if requested
    if args.shuffle:
        shuf = np.arange(args.n_regions)
        np.random.shuffle(shuf)
        parts = list(map(lambda x : shuf[x], parts))

    # Add the part array
    vtk_polydata_append_array(pd, np.array(parts), "MetisPart")

# Generate output mesh
vtk_polydata_set_points(pd, va)
vtk_save_mesh(pd, args.result)
