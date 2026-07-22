#!/bin/bash

set -u

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 runs.txt workflow_tag"
  echo "Example: $0 runs.txt cross_with_hcal_09"
  exit 1
fi

RUNFILE="$1"
WORKFLOW_TAG="$2"
OUTDIR="/volatile/halla/sbs/btspaude/cdet"

if [ ! -f "$RUNFILE" ]; then
  echo "Error: file '$RUNFILE' not found"
  exit 1
fi

if [ -z "$WORKFLOW_TAG" ]; then 
  echo "Error: workflow tag cannot be empty"
  exit 1
fi

while IFS= read -r run || [ -n "$run" ]; do
  # Skip blank lines
  if [ -z "$run" ]; then
    continue
  fi

  # Skip comment lines starting with #
  case "$run" in
    \#*) continue ;;
  esac

  workflow="cdet_${run}_${WORKFLOW_TAG}"

  echo "Submitting run ${run} with workflow ${workflow}"

  ./submit-cdet-jobs.sh "${run}" -1 0 100 0 <<EOF
n
${workflow}
/volatile/halla/sbs/btspaude/cdet
EOF

  echo "Finished run ${run}"
  echo

done < "$RUNFILE"
