#!/usr/bin/env bash
# run-cdet-replay-slurm.sh
# Minimal, SLURM-array-friendly runner for CDet/GMn replays.
# Designed to be invoked by an sbatch array wrapper, not submitted directly.
#
# Accepts either positional args (for manual debugging) or env vars when
# launched by the array wrapper.
#
# Positional (optional, overrides env):
#   1: RUNNUM
#   2: NEVENTS      (0 = all)
#   3: CONFIG       (e.g., gep5)
#   4: SEGMENT      (0-based)
#   5: OUTDIR
#
set -euo pipefail
IFS=$'\n\t'

# ---- Inputs (env defaults) -------------------------------------------------
RUNNUM="${1:-${RUNNUM:-}}"
NEVENTS="${2:-${NEVENTS:-0}}"
CONFIG="${3:-${CONFIG:-gep5}}"
SEGMENT="${4:-${SEGMENT:-0}}"
OUTDIR="${5:-${OUTDIR:-$PWD/out}}"

DATA_DIR="${DATA_DIR:-/work/brash/sbs/GEp/raw}"
SCRIPT_DIR="${SCRIPT_DIR:-}"
ANALYZER="${ANALYZER:-}"
SBSOFFLINE="${SBSOFFLINE:-}"
SBS_REPLAY="${SBS_REPLAY:-${SBSREPLAY:-}}"
ANAVER="${ANAVER:-}"
useJLABENV="${useJLABENV:-0}"
JLABENV="${JLABENV:-/group/jlabenv}"

if [[ -z "${RUNNUM}" ]]; then
  echo "RUNNUM is required (arg1 or env RUNNUM)"; exit 2
fi

# ---- Setup dirs ------------------------------------------------------------
mkdir -p "${OUTDIR%/}/rootfiles" "${OUTDIR%/}/logs"
LOG="${OUTDIR%/}/logs/run_${RUNNUM}_seg_${SEGMENT}.log"

# Work dir: SLURM provides $SLURM_TMPDIR on many systems; fallback to mktemp
WORKDIR="${SLURM_TMPDIR:-$(mktemp -d)}"
trap 'rm -rf "$WORKDIR"' EXIT

echo "== CDet replay =="
echo "Run:      $RUNNUM"
echo "Segment:  $SEGMENT"
echo "Config:   $CONFIG"
echo "Nevents:  $NEVENTS"
echo "Outdir:   $OUTDIR"
echo "Workdir:  $WORKDIR"
echo "Host:     $(hostname)"
echo "SLURM:    JOBID=${SLURM_JOB_ID:-} TASKID=${SLURM_ARRAY_TASK_ID:-}"

# ---- Input file(s) ---------------------------------------------------------
# Adjust naming pattern to match your raw data filenames.
RAW="${DATA_DIR%/}/gep5_${RUNNUM}.evio.0.${SEGMENT}"
if [[ ! -f "$RAW" ]]; then
  echo "[skip] Missing raw file: $RAW" | tee -a "$LOG"
  exit 0
fi

# ---- Environment (ROOT / analyzer) ----------------------------------------
# Source your experiment environment if needed
if [[ -f "./setenv.sh" ]]; then
  # shellcheck disable=SC1091
  source ./setenv.sh
fi

# Optionally manipulate ROOT settings in the work dir
pushd "$WORKDIR" >/dev/null
if [[ -f "$HOME/.rootrc" ]]; then
  cp "$HOME/.rootrc" .rootrc_temp
  cp "$HOME/.rootrc" .rootrc
fi

# ---- Replay invocation -----------------------------------------------------
# Replace the line below with your exact command if different.
# Signature mirrors the original wrapper you shared:
#   replay_gmn.sh <runnum> <nevents> <???=0> <config> <segment> <???=1>
#                 <DATA_DIR> <OUTDIR> <runnum> <ANALYZER> <SBSOFFLINE> <SBS_REPLAY> <ANAVER> <useJLABENV> <JLABENV>
set +e
"${SCRIPT_DIR%/}/replay_gmn.sh" "$RUNNUM" "$NEVENTS" 0 "$CONFIG" "$SEGMENT" 1 \
  "$DATA_DIR" "$OUTDIR" "$RUNNUM" "$ANALYZER" "$SBSOFFLINE" "$SBS_REPLAY" "$ANAVER" "$useJLABENV" "$JLABENV" \
  >"$LOG" 2>&1
RC=$?
set -e
echo "Replay exit code: $RC" | tee -a "$LOG"

# ---- Output handling -------------------------------------------------------
# If you know the exact naming of the produced root file, set it here.
# The previous script used something like $outfilename. We'll try a few heuristics:
OUTROOT=""
for f in "replay_gmn_${RUNNUM}_${SEGMENT}.root" "gmn_${RUNNUM}_${SEGMENT}.root" "e${RUNNUM}_${SEGMENT}.root"; do
  if [[ -f "$f" ]]; then OUTROOT="$f"; break; fi
done

if [[ -n "$OUTROOT" ]]; then
  mkdir -p "${OUTDIR%/}/rootfiles"
  cp -f "$OUTROOT" "${OUTDIR%/}/rootfiles/"
  echo "Copied $OUTROOT -> ${OUTDIR%/}/rootfiles/" | tee -a "$LOG"
else
  echo "WARNING: No expected ROOT output found in $WORKDIR" | tee -a "$LOG"
fi

# Restore .rootrc if we modified it
if [[ -f .rootrc_temp ]]; then
  mv -f .rootrc_temp .rootrc
  rm -f .rootrc
fi
popd >/dev/null

exit "$RC"
