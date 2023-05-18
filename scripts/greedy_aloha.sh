#!/bin/bash
set -x -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fixed image
FIXED=${1?}

# Moving image
MOVING=${2?}

# Fixed segmentation, single label
FIXSEG=${3?}

# Work directory
WORK=${4?}

# JSON parameter file
PARAM=${5?}

# Create work directory
mkdir -p $WORK

export NSLOTS=1


function set_common_vars()
{
    # Define variables
    FIXSEG_DIL=$WORK/fixseg_dilate.nii.gz
    WBRIGID=$WORK/whole_brain_rigid.mat
    WBRIGID_INV=$WORK/whole_brain_rigid_inv.mat

    FIXED_ROI=$WORK/fixed_roi.nii.gz
    FIXSEG_ROI_DIL=$WORK/fixseg_roi_dilate.nii.gz
    MOVING_ROI=$WORK/moving_roi.nii.gz
    ROIRIGID=$WORK/roi_rigid.mat

    ROIRIGID_TCOMP=$WORK/roi_rigid_tcomp.mat

    ROIRIGID_SQRT=$WORK/roi_rigid_sqrt.mat
    ROIRIGID_ISQRT=$WORK/roi_rigid_iqsrt.mat

    FIXED_HW=$WORK/fixed_hw.nii.gz
    MOVING_HW=$WORK/moving_hw.nii.gz
    FIXSEG_DIL_HW=$WORK/fixseg_dilate_hw.nii.gz
    METRIC_RIGID=$WORK/metric_rigid_${expid}.txt

    FIXSEG_GM=$WORK/fixseg_gm_binary.nii.gz
    FIXSEG_GM_MESH=$WORK/fixseg_gm_mesh.vtk
    FIXSEG_GM_MESH_METIS=$WORK/fixseg_gm_mesh_metis.vtk
    FIXSEG_GM_MESH_TETRA=$WORK/fixseg_gm_mesh_tetra.vtk
    FIXSEG_GM_MESH_SKEL=$WORK/fixseg_gm_mesh_skel.vtk
    FIXSEG_GM_MESH_TETRA_HW=$WORK/fixseg_gm_mesh_tetra_hw.vtk

    TETRASTAT_HW=$WORK/tetra_stats_hw.vtk
    TETRASTAT_FIXED=$WORK/tetra_stats_fixed.vtk

    STATS_VOLUME=$WORK/stats_volume.csv
    STATS_THICKNESS=$WORK/stats_thickness.csv
}

function set_per_label_vars()
{
    label=${1?}
    
    # Each label should have a separate directory
    LID=$(printf "label%03d" $label)
    LABELDIR=$WORK/labels/$LID

    # Mesh of the label
    LABEL_BINARY_SEG_FIXED=$LABELDIR/${LID}_binary_seg_fixed.nii.gz
    LABEL_MESH_FIXED=$LABELDIR/${LID}_mesh_fixed.vtk
    LABEL_MESH_SMOOTH=$LABELDIR/${LID}_mesh_taubin_smooth.vtk
    LABEL_MESH_HW=$LABELDIR/${LID}_mesh_hw.vtk
    LABEL_SKEL_HW=$LABELDIR/${LID}_mesh_hw_skel.vtk
    LABEL_SKEL_HW_STDOUT=$LABELDIR/${LID}_mesh_hw_skel_stdout.txt
}

function set_def_exp_vars()
{
    expid=${1?}
    WARPROOT=$WORK/warproot_${expid}.nii.gz

    FIXED_HW_WARPED=$WORK/fixed_hw_warped_${expid}.nii.gz
    MOVING_HW_WARPED=$WORK/moving_hw_warped_${expid}.nii.gz

    METRIC_DEFORM=$WORK/metric_deform_${expid}.txt

    FIXSEG_GM_MESH_TETRA_HW_WARPED=$WORK/fixseg_gm_mesh_tetra_hw_warped_${expid}.vtk
}

function set_per_label_def_exp_vars()
{
    label=${1?}
    expid=${2?}

    LABEL_MESH_WARPED=$LABELDIR/${LID}_hw_warped_${expid}.vtk
    LABEL_SKEL_WARPED=$LABELDIR/${LID}_hw_warped_skel_${expid}.vtk
    LABEL_SKEL_WARPED_STDOUT=$LABELDIR/${LID}_hw_warped_skel_stdout_${expid}.txt
}

# Parse the labels
LABELS_FG_COUNT=$(jq '.foreground_labels | length' < $PARAM)
declare -a LABELS_FG_IDS
declare -a LABELS_FG_NAMES
LABELS_FG_REPLACE_CMD=""

for ((i=0; i < $LABELS_FG_COUNT; i++)); do
    label_id=$(jq -r ".foreground_labels[$i].id" < $PARAM)
    LABELS_FG_IDS[i]=$label_id
    LABELS_FG_NAMES[i]=$(jq -r ".foreground_labels[$i].name" < $PARAM)
    LABELS_FG_REPLACE_CMD="$LABELS_FG_REPLACE_CMD $label_id 999"
done

# Parse the experiments
N_EXP=$(jq '.deformable_param | length' < $PARAM)

# Set the main variables
set_common_vars

# Dilate the segmentation
c3d $FIXSEG -thresh 1 inf 1 0 -dilate 1 10x10x10vox -type short -o $FIXSEG_DIL

# Perform whole-brain rigid registration
greedy -d 3 -a -dof 6 -i $FIXED $MOVING \
    -m NCC 2x2x2 -n 100x100x40x0x0 -ia-image-centers -o $WBRIGID

# Extract fixed and moving ROIs
c3d $FIXSEG_DIL -trim 5vox -type short -o $FIXSEG_ROI_DIL \
    $FIXED -reslice-identity -type float -o $FIXED_ROI
c3d_affine_tool $WBRIGID -inv -o $WBRIGID_INV
c3d $MOVING -as M $FIXSEG_DIL -reslice-matrix $WBRIGID_INV -thresh 0.5 inf 1 0 \
    -trim 5vox -push M -reslice-identity -o $MOVING_ROI

# Perform regional rigid registration
greedy -d 3 -a -dof 6 -i $FIXED_ROI $MOVING_ROI \
    -m NCC 2x2x2 -n 100x40x0 -ia $WBRIGID -gm $FIXSEG_ROI_DIL -o $ROIRIGID

# Halfway space might be outside of the fixed image space due to translation
# so find a voxel-space translation 
$SCRIPT_DIR/centertfm.py $FIXED_ROI $MOVING_ROI > $ROIRIGID_TCOMP

# Work out the half-transforms from fixed and moving spaces
c3d_affine_tool $ROIRIGID $ROIRIGID_TCOMP -inv -mult -sqrt $ROIRIGID_TCOMP -mult -o $ROIRIGID_SQRT
c3d_affine_tool $ROIRIGID_SQRT -inv $ROIRIGID_TCOMP -mult -o $ROIRIGID_ISQRT

# Apply half-transforms to the moving/fixed ROIs and mask
greedy -d 3 -rf $FIXED_ROI -rm $MOVING_ROI $MOVING_HW -r $ROIRIGID_SQRT
greedy -d 3 -rf $FIXED_ROI -rm $FIXED_ROI $FIXED_HW \
    -ri LABEL 0.2vox -rm $FIXSEG_ROI_DIL $FIXSEG_DIL_HW \
    -r $ROIRIGID_ISQRT

# Compute metric after rigid registration
greedy -d 3 -i $FIXED_HW $MOVING_HW -m NCC 2x2x2 -gm $FIXSEG_DIL_HW -metric \
    | grep 'Total =' | awk '{print $6}' > $METRIC_RIGID

# Extract the gray matter parts of the segmentation
c3d $FIXSEG -replace $LABELS_FG_REPLACE_CMD -thresh 999 999 1 0 -o $FIXSEG_GM

# Generate a surface mesh of the segmentation and smooth/parcellate it
vtklevelset -f $FIXSEG_GM $FIXSEG_GM_MESH 0.5

$SCRIPT_DIR/mesh_partition_metis.py -r -n 200 -s 50 $FIXSEG_GM_MESH $FIXSEG_GM_MESH_METIS

# Generate the fixed space tetrahedral mesh
cmrep_vskel -Q qvoronoi -e 4 -p 0.0 \
    -d $FIXSEG_GM_MESH_TETRA $FIXSEG_GM_MESH_METIS $FIXSEG_GM_MESH_SKEL

# Extract per-label meshes and send them to half-way space
PER_LABEL_RS_CMD=""
for label in ${LABELS_FG_IDS[@]}; do
    set_per_label_vars $label

    mkdir -p $LABELDIR
    c3d $FIXSEG -thresh $label $label 1 0 -type uchar -o $LABEL_BINARY_SEG_FIXED
    vtklevelset -f $LABEL_BINARY_SEG_FIXED $LABEL_MESH_FIXED 0.5
    $SCRIPT_DIR/mesh_partition_metis.py -n 0 -s 50 $LABEL_MESH_FIXED $LABEL_MESH_SMOOTH

    PER_LABEL_RS_CMD="$PER_LABEL_RS_CMD -rs $LABEL_MESH_SMOOTH $LABEL_MESH_HW"
done

# Map tetra mesh and per-label meshes into the halfway space
greedy -d 3 -rf $FIXED_ROI -rs $FIXSEG_GM_MESH_TETRA $FIXSEG_GM_MESH_TETRA_HW $PER_LABEL_RS_CMD -r $ROIRIGID_ISQRT,-1

# Copy the mesh for stats collection
cp -av $FIXSEG_GM_MESH_TETRA_HW $TETRASTAT_HW

# Define a set of registration experiments with different parameters
for ((i=0;i<$N_EXP;i++)); do

    # This is the ID of this experiment
    expid=$(printf "exp%03d" $i)
    set_def_exp_vars $expid

    # Load the parameters
    SIGMAS=$(jq -r ".deformable_param[$i].sigma" < $PARAM)

    # Perform deformable registration
    greedy -d 3 -i $FIXED_HW $MOVING_HW -gm $FIXSEG_DIL_HW -oroot $WARPROOT \
        -wp 0 -sv -m NCC 2x2x2 \
        -s $SIGMAS -n 100x60

    # Apply registration in halfway space
    greedy -d 3 -rf $FIXED_HW -rm $MOVING $MOVING_HW_WARPED -r $WARPROOT,32 $ROIRIGID_SQRT
    greedy -d 3 -rf $FIXED_HW -rm $FIXED $FIXED_HW_WARPED -r $WARPROOT,-32 $ROIRIGID_ISQRT

    # Compute the metric between them
    greedy -d 3 -i $FIXED_HW_WARPED $MOVING_HW_WARPED -m NCC 2x2x2 -gm $FIXSEG_DIL_HW -metric \
        | grep 'Total =' | awk '{print $6}' > $METRIC_DEFORM

    # Generate the command for warping per-label meshes
    PER_LABEL_RS_CMD=""
    for label in ${LABELS_FG_IDS[*]}; do
        set_per_label_vars $label
        set_per_label_def_exp_vars $label $expid
        PER_LABEL_RS_CMD="$PER_LABEL_RS_CMD -rs $LABEL_MESH_HW $LABEL_MESH_WARPED"
    done

    # Apply the warp to the tetrahedral mesh
    greedy -d 3 -rf $FIXED_ROI -rs $FIXSEG_GM_MESH_TETRA_HW $FIXSEG_GM_MESH_TETRA_HW_WARPED $PER_LABEL_RS_CMD -r $WARPROOT,64

    # Compute the tetra radii and volumes
    $SCRIPT_DIR/compute_thickness_delta.py -e $expid $TETRASTAT_HW $FIXSEG_GM_MESH_TETRA_HW_WARPED $TETRASTAT_HW

done

# Map the tetra radii back to native space
greedy -d 3 -rf $FIXED_ROI -rs $TETRASTAT_HW $TETRASTAT_FIXED -r $ROIRIGID_ISQRT


# Compute per-label values (thickness, volume)
echo "Label,ExpId,Volume,VolumeAtrophy" > $STATS_VOLUME
echo "Label,ExpId,Thickness,ThicknessAtrophy" > $STATS_THICKNESS
for label in ${LABELS_FG_IDS[*]}; do
    set_per_label_vars $label

    # Loop over the experiments
    for ((i=0;i<$((N_EXP+1));i++)); do

        if [[ $i -eq 0 ]]; then
            expid="baseline"
            MESH=$LABEL_MESH_HW
            SKEL=$LABEL_SKEL_HW
            STDOUT=$LABEL_SKEL_HW_STDOUT
        else
            expid=$(printf "exp%03d" $((i-1)))
            set_per_label_def_exp_vars $label $expid
            MESH=$LABEL_MESH_WARPED
            SKEL=$LABEL_SKEL_WARPED
            STDOUT=$LABEL_SKEL_WARPED_STDOUT
        fi

        # Skeletonize baseline mesh
        cmrep_vskel -Q qvoronoi -e 4 -p 1.2 \
            $MESH $SKEL 2>/dev/null | tee $STDOUT

        # Compute the volume statistics
        meshdiff -s 0.25 $MESH $MESH | tee -a $STDOUT

        # Extract the mean thickness
        THK=$(cat $STDOUT | grep 'Mean thickness:' | awk '{print $3}')
        VOL=$(cat $STDOUT | grep 'Mesh 1 Volume' | awk '{print $5}')

        # Set the reference volumes
        if [[ $i -eq 0 ]]; then
            REFVOL=$VOL
            REFTHK=$THK
        fi

        echo $label,$expid,$VOL,$(echo $VOL $REFVOL | awk '{print ($2-$1)/$2}') >> $STATS_VOLUME
        echo $label,$expid,$THK,$(echo $THK $REFTHK | awk '{print ($2-$1)/$2}') >> $STATS_THICKNESS

    done

done
 
