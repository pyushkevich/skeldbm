# skeldbm
Skeleton DBM scripts and dockerfiles

## About
SkelDBM is a set of scripts for performing deformation-based morphometry on the hippocampus and extrahippocampal medial temporal lobe gray matter structures based on skeletons. It should be used in conjunction with the [ASHS-T1](https://sites.google.com/view/ashs-dox/quick-start#h.p_DFL0QLEDu_F8) segmentation tool.

This repository includes the SkelDBM code and a `Dockerfile`. The container on DockerHub is labeled `pyushkevich/skeldbm:latest`

The main script is located in `/tk/skeldbm/scripts/skeldbm.sh`. Run it with `-h` option to see usage. There is also a script that you can run on a sample dataset, `run_sample.sh`.
