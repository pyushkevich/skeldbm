#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
D=$(dirname $SCRIPT_DIR)/sample_data
${SCRIPT_DIR}/skeldbm.sh -i test -p $D/param.json -b $D/blsr.nii.gz -f $D/fusr.nii.gz -l $D/segl.nii.gz -r $D/segr.nii.gz -d -w /tmp/work
