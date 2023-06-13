# skeldbm
Skeleton DBM scripts and dockerfiles

## About
SkelDBM is a set of scripts for performing deformation-based morphometry on the hippocampus and extrahippocampal medial temporal lobe gray matter structures based on skeletons. It should be used in conjunction with the [ASHS-T1](https://sites.google.com/view/ashs-dox/quick-start#h.p_DFL0QLEDu_F8) segmentation tool.

This repository includes the SkelDBM code and a `Dockerfile`. The official container on DockerHub is labeled `pyushkevich/skeldbm:latest`

To run this script, you will need the following inputs:

1. A super-resolution T1-MRI scan from the baseline image (`tse.nii.gz` in the T1-ASHS directory).
2. A super-resolution T1-MRI scan from the followup image (`tse.nii.gz` in the T1-ASHS directory).
3. The T1-ASHS segmentation of the left MTL from the baseline image (e.g., `final/xyz_lfseg_left_corr_usegray.nii.gz` in the T1-ASHS directory).
4. The T1-ASHS segmentation of the right MTL from the baseline image (e.g., `final/xyz_lfseg_right_corr_usegray.nii.gz` in the T1-ASHS directory).
5. A parameter file (see `sampledata/param.json`)

If using the Docker container, run

    docker run -v your_data_directory:/data -it pyushkevich/skeldbm:latest /bin/bash
    scripts/skeldbm.sh -h
    
This will print the following instructions

    SkelDBM script
    Usage: ./skeldbm.sh [options]
    Options:
      -i <string>    : Subject/experiment ID to prepend to filenames
      -b <file>      : Path to baseline super-resolution T1-MRI image
      -f <file>      : Path to followup super-resolution T1-MRI image
      -l <file>      : Path to ASHS-T1 left segmentation of the baseline image
      -r <file>      : Path to ASHS-T1 right segmentation of the baseline image
      -w <path>      : Output directory (will be created)
      -p <file>      : Path to JSON parameter file
      -t <int>       : Number of CPU threads to use for registration (default: 1)
      -d             : Enable debugging output
    Relevant Outputs (in directories greedy_aloha_left/greedy_aloha_right):
      <id>_fixseg_gm_mesh_tetra_hw_tjr_jacobian.vtk : Tetrahedral mesh with
                       the Jacobian of the computed deformation. In the half-way space.
      <id>_warproot_tjr.nii.gz : Stationary velocity field for the deformation
                       between the baseline and follow-up images in halfway space
      roi_rigid_iqsrt.mat: Rigid transform from halfway space to baseline image space

Run this with your data, which inside the container will be located in the `/data` directory.

## Sample Dataset
A sample dataset is located in `sample_data`. Execute SkelDBM on the sample dataset using script `scripts/run_sample.sh`

    docker run -it pyushkevich/skeldbm:latest /bin/bash
    scripts/run_sample.sh
    
## Related Projects
* ''ASHS'': automatic segmentation of hippocampal subfields ([docs](https://sites.google.com/view/ashs-dox/home), [github](https://github.com/pyushkevich/ashs))
* ''CrASHS'': surface-based pipeline for matching T1-ASHS segmentations to a template ([github](https://github.com/pyushkevich/crashs))
    
