#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function usage()
{
    echo "SkelDBM script"
    echo "Usage: ./skeldbm.sh [options]"
    echo "Options:"
    echo "  -i <string>    : Subject/experiment ID to prepend to filenames"
    echo "  -b <file>      : Path to baseline super-resolution T1-MRI image"
    echo "  -f <file>      : Path to followup super-resolution T1-MRI image"
    echo "  -l <file>      : Path to ASHS-T1 left segmentation of the baseline image"
    echo "  -r <file>      : Path to ASHS-T1 right segmentation of the baseline image"
    echo "  -w <path>      : Output directory (will be created)"
    echo "  -p <file>      : Path to JSON parameter file"
    echo "  -t <int>       : Number of CPU threads to use for registration (default: 1)"
    echo "  -d             : Enable debugging output"
    echo "Relevant Outputs (in directories greedy_aloha_left/greedy_aloha_right):"
    echo "  <id>_fixseg_gm_mesh_tetra_hw_tjr_jacobian.vtk : Tetrahedral mesh with"
    echo "                   the Jacobian of the computed deformation. In the half-way space."
    echo "  <id>_warproot_tjr.nii.gz : Stationary velocity field for the deformation"
    echo "                   between the baseline and follow-up images in halfway space"
    echo "  roi_rigid_iqsrt.mat: Rigid transform from halfway space to baseline image space"
}

# Read the command-line options
NSLOTS=1
while getopts "dhb:f:l:r:w:p:t:i:" opt; do
  case $opt in
    d) set -x;;
    i) ID=$OPTARG;;
    b) SRBL=$OPTARG;;
    f) SRFU=$OPTARG;;
    l) SEGL=$OPTARG;;
    r) SEGR=$OPTARG;;
    w) WORK=$OPTARG;;
    p) PJSON=$OPTARG;;
    t) NSLOTS=$OPTARG;;
    h) usage; exit 0;;
    \?) echo "Unknown option $OPTARG"; exit 2;;
    :) echo "Option $OPTARG requires an argument"; exit 2;;
  esac
done

# Check the parameters
echo "Subject/Experiment Id: ${ID?}"
echo "Parameter JSON file: ${PJSON?}"
echo "Baseline T1-SR scan: ${SRBL?}"
echo "Followup T1-SR scan: ${SRFU?}"
echo "Left segmentation: ${SEGL?}"
echo "Right segmentation: ${SEGR?}"
echo "Work directory: ${WORK?}"

# Read the regularization weights from the JSON
WR=$(jq -r ".skeldbm_param.wr" < ${PJSON})
WTJR=$(jq -r ".skeldbm_param.wtjr" < ${PJSON})
ITER_TJR=$(jq -r ".skeldbm_param.iterations | 1000" < ${PJSON})
echo "Optimization parameters: GradDefWgt(wr):${WR?} TetraJacobianWgt(wtjr): ${WTJR?} Iterations: ${ITER_TJR}"

# Repeat processing for both sides
for side in left right; do

    # Pick the correct segmentation
    if [[ $side == "left" ]]; then SEG=${SEGL}; else SEG=${SEGR}; fi

    # Run the greedy aloha script
    ALOHA_DIR=$WORK/${ID}_greedy_aloha_${side}
    mkdir -p $ALOHA_DIR
    $SCRIPT_DIR/greedy_aloha.sh $SRBL $SRFU $SEG $ALOHA_DIR $PJSON

    # Set the image variables
    ALOHA_TJR_REGDUMP=$ALOHA_DIR/greedy_output_tjr.txt
    ALOHA_FIX_ROI=$ALOHA_DIR/fixed_roi.nii.gz
    ALOHA_FIX_HW=$ALOHA_DIR/fixed_hw.nii.gz
    ALOHA_MOV_HW=$ALOHA_DIR/moving_hw.nii.gz
    ALOHA_FIXMASK_HW=$ALOHA_DIR/fixseg_dilate_hw.nii.gz
    ALOHA_TETRA_HW=$ALOHA_DIR/fixseg_gm_mesh_tetra_hw.vtk
    ALOHA_TETRA_FIX=$ALOHA_DIR/fixseg_gm_mesh_tetra.vtk
    ALOHA_ROI_RIGID_ISQRT=$ALOHA_DIR/roi_rigid_iqsrt.mat
    ALOHA_GREEDY_WARPROOT=$ALOHA_DIR/warproot_exp000.nii.gz
    ALOHA_TJR_WARPROOT=$ALOHA_DIR/${ID}_warproot_tjr.nii.gz
    ALOHA_TETRA_HW_TJR_JACOBIAN=$ALOHA_DIR/${ID}_fixseg_gm_mesh_tetra_hw_tjr_jacobian.vtk
    ALOHA_TETRA_HW_TJR_VOLSTAT=$ALOHA_DIR/${ID}_fixseg_gm_mesh_tetra_hw_tjr_volstat.csv

    # Run the registration with the mesh regularization using the new 
    # -defopt functionality
    greedy -d 3 -threads $NSLOTS -defopt \
        -i $ALOHA_FIX_HW $ALOHA_MOV_HW \
        -gm $ALOHA_FIXMASK_HW -m NCC 2x2x2 \
        -oroot $ALOHA_TJR_WARPROOT \
        -n ${ITER_TJR} -wr $WR -noise 0 -s 2.0vox 0.1vox \
        -tjr $ALOHA_TETRA_HW $WTJR \
        | tee $ALOHA_TJR_REGDUMP

    # Compute the Jacobian of the deformation in mesh space
    greedy -d 3 -threads 1 \
        -rf $ALOHA_FIX_HW \
        -rsj $ALOHA_TETRA_HW $ALOHA_TETRA_HW_TJR_JACOBIAN \
        -r $ALOHA_TJR_WARPROOT,64

    # Get rid of the labels directory - lots of wasted space
    if [[ -d $ALOHA_DIR/labels ]]; then
        rm -rf $ALOHA_DIR/labels
    fi

    # Compute the volume statistics using TJR regularization
    $SCRIPT_DIR/tjr_roi_volumes.py -m $ALOHA_TETRA_FIX -j $ALOHA_TETRA_HW_TJR_JACOBIAN \
        -s $SEG -i "$ID,$side" \
        > $ALOHA_TETRA_HW_TJR_VOLSTAT

done


    


        



