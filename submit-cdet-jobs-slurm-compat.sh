#!/usr/bin/env bash
# ------------------------------------------------------------------------- #
# submit-cdet-jobs-slurm-compat.sh
# SLURM job-array port of the original swif2-based submit-cdet-jobs.sh.
# Preserves a 5-argument CLI: RUNLIST NEVENTS NSEGMENTS OUTDIR RUN_ON_IFARM
# ------------------------------------------------------------------------- #
# Example:
#   ./submit-cdet-jobs-slurm-compat.sh runs.txt 500000 8 /work/halla/sbs/$USER/gmn/out 0
#   (Use 1 for RUN_ON_IFARM to run locally in a for-loop without SLURM.)
# ------------------------------------------------------------------------- #

set -euo pipefail
IFS=$'\n\t'

# --- Load the same environments as the original script -------------------- #
# (Edit path if your setenv.sh is elsewhere.)
if [[ -f ./setenv.sh ]]; then
  source ./setenv.sh
fi

# Common JLab variables seen in the original script. Override here if needed.
: "${DATA_DIR:=/cache/mss/halla/sbs/GEp/raw}"
: "${SCRIPT_DIR:=${SCRIPT_DIR:-}}"
: "${ANALYZER:=${ANALYZER:-}}"
: "${SBSOFFLINE:=${SBSOFFLINE:-}}"
: "${SBS_REPLAY:=${SBS_REPLAY:-${SBSREPLAY:-}}}"
: "${ANAVER:=${ANAVER:-}}"
: "${useJLABENV:=${useJLABENV:-0}}"
: "${JLABENV:=${JLABENV:-/group/jlabenv}}"

# --- Args: keep the original 5-arg contract --------------------------------
if [[ "$#" -ne 5 ]]; then
  echo ""
  echo "Illegal number of arguments."
  echo "Usage: $0 RUNLIST NEVENTS NSEGMENTS OUTDIR RUN_ON_IFARM"
  echo ""
  echo "  RUNLIST       Text file with one run number per line (comments ok)."
  echo "  NEVENTS       Events per segment (0 = all)."
  echo "  NSEGMENTS     Number of segments/chunks per run."
  echo "  OUTDIR        Output directory (created if missing)."
  echo "  RUN_ON_IFARM  1 = run locally in a loop (no SLURM); 0 = use SLURM array."
  echo ""
  exit 1
fi

RUNLIST="$1"
NEVENTS="$2"
NSEGMENTS="$3"
OUTDIR="$4"
RUN_ON_IFARM="$5"

# --- Basic checks matching the old script's spirit --------------------------
if [[ ! -f "$RUNLIST" ]]; then
  echo "Runlist not found: $RUNLIST" >&2
  exit 2
fi

# Check required envs referenced by the old script
if [[ -z "${SCRIPT_DIR:-}" ]]; then
  echo 'ERROR: SCRIPT_DIR is empty (should be set by setenv.sh)' >&2; exit 2
fi
if [[ ! -d "${SBSOFFLINE:-/nonexistent}" ]]; then
  echo 'ERROR: SBSOFFLINE dir not found.' >&2; exit 2
fi
if [[ ! -d "${SBS_REPLAY:-/nonexistent}" ]]; then
  echo 'ERROR: SBS_REPLAY dir not found.' >&2; exit 2
fi
if [[ "${useJLABENV:-0}" -eq 1 && ! -d "${ANALYZER:-/nonexistent}" ]]; then
  echo 'ERROR: ANALYZER dir not found (required when useJLABENV=1).' >&2; exit 2
fi

mkdir -p "$OUTDIR"
LOGDIR="${OUTDIR%/}/logs"
mkdir -p "$LOGDIR"

# --- Build flat task list: (run, seg) pairs ---------------------------------
# The original loop nested over run numbers and segments. We mimic that and
# then map to a single SLURM_ARRAY_TASK_ID.
mapfile -t RUNS < <(grep -E '^[[:space:]]*[0-9]+' "$RUNLIST" | sed -E 's/#.*//' | awk '{print $1}')
if [[ "${#RUNS[@]}" -eq 0 ]]; then
  echo "No runs found in $RUNLIST" >&2
  exit 2
fi

if ! [[ "$NSEGMENTS" =~ ^[0-9]+$ ]] || [[ "$NSEGMENTS" -lt 1 ]]; then
  echo "NSEGMENTS must be a positive integer. Got: $NSEGMENTS" >&2
  exit 2
fi

TASKS=$(( ${#RUNS[@]} * NSEGMENTS ))
echo "TOTAL TASKS: $TASKS  (runs=${#RUNS[@]} x segs=$NSEGMENTS)"
echo "Logs: $LOGDIR"
echo "Out : $OUTDIR"

# Helper to compute run & seg from a flat index k
emit_indexer() {
  cat <<'BASH'
run_from_index() {
  local idx="$1" nseg="$2"; shift || true
  local rindex=$(( idx / nseg ))
  echo "$rindex"
}
seg_from_index() {
  local idx="$1" nseg="$2"; shift || true
  local sindex=$(( idx % nseg ))
  echo "$sindex"
}
BASH
}

# --- LOCAL LOOP MODE (RUN_ON_IFARM=1) ---------------------------------------
if [[ "$RUN_ON_IFARM" -eq 1 ]]; then
  echo "Running locally (no SLURM)."
  eval "$(emit_indexer)"
  for ((k=0; k< TASKS; k++)); do
    rindex=$(run_from_index "$k" "$NSEGMENTS")
    sindex=$(seg_from_index "$k" "$NSEGMENTS")
    RUNNUM="${RUNS[$rindex]}"
    SEG="$sindex"
    LOG="$LOGDIR/run_${RUNNUM}_seg_${SEG}.log"

    # --- Input file precheck (mimic original cache check; adapt as needed) ---
    CACHEFILE="${DATA_DIR%/}/e${RUNNUM}.dat"
    if [[ ! -f "$CACHEFILE" ]]; then
      echo "[skip] cache file missing for run $RUNNUM: $CACHEFILE" | tee -a "$LOG"
      continue
    fi

    echo "[LOCAL] RUN=$RUNNUM SEG=$SEG NEVENTS=$NEVENTS -> $LOG"
    set +e
    # NOTE: Replace the following replay invocation line with your exact command.
    #       The original script passed many env-based paths; we continue to pass them.
    "${SCRIPT_DIR%/}/run-cdet-replay-slurm.sh" "$RUNNUM" "$NEVENTS" 0 "gep5" "$SEG" 1 \
      "$DATA_DIR" "$OUTDIR" "$RUNNUM" "$ANALYZER" "$SBSOFFLINE" "$SBS_REPLAY" "$ANAVER" "$useJLABENV" "$JLABENV" \
      >"$LOG" 2>&1
    RC=$?
    set -e
    echo "Run $RUNNUM seg $SEG -> exit $RC (log: $LOG)"
  done
  exit 0
fi

# --- SLURM ARRAY MODE -------------------------------------------------------
command -v sbatch >/dev/null 2>&1 || { echo "sbatch not found in PATH."; exit 2; }

ARRAY_RANGE="0-$((TASKS-1))"
WRAPPER="${LOGDIR%/}/array_task.sh"

cat > "$WRAPPER" <<'TASK'
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Inherit exported envs
RUNLIST="${RUNLIST}"
NEVENTS="${NEVENTS}"
NSEGMENTS="${NSEGMENTS}"
OUTDIR="${OUTDIR}"
DATA_DIR="${DATA_DIR}"
SCRIPT_DIR="${SCRIPT_DIR}"
ANALYZER="${ANALYZER}"
SBSOFFLINE="${SBSOFFLINE}"
SBS_REPLAY="${SBS_REPLAY}"
ANAVER="${ANAVER}"
useJLABENV="${useJLABENV}"
JLABENV="${JLABENV}"

# Build the run array on the fly (same filter as launcher)
mapfile -t RUNS < <(grep -E '^[[:space:]]*[0-9]+' "$RUNLIST" | sed -E 's/#.*//' | awk '{print $1}')

run_from_index() { local idx="$1" nseg="$2"; echo $(( idx / nseg )); }
seg_from_index() { local idx="$1" nseg="$2"; echo $(( idx % nseg )); }

IDX="${SLURM_ARRAY_TASK_ID:-0}"
RINDEX="$(run_from_index "$IDX" "$NSEGMENTS")"
SINDEX="$(seg_from_index "$IDX" "$NSEGMENTS")"

RUNNUM="${RUNS[$RINDEX]}"
SEG="$SINDEX"

LOGDIR="${OUTDIR%/}/logs"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/run_${RUNNUM}_seg_${SEG}.log"

echo "SLURM_TASK_ID=$SLURM_ARRAY_TASK_ID -> RUN=$RUNNUM SEG=$SEG"

# Input file precheck (adapt to your data naming)
CACHEFILE="${DATA_DIR%/}/e${RUNNUM}.dat"
if [[ ! -f "$CACHEFILE" ]]; then
  echo "[skip] cache file missing for run $RUNNUM: $CACHEFILE" | tee -a "$LOG"
  exit 0
fi

# ---- REPLAY INVOCATION (match your original) ------------------------------
# Replace with your actual script/cmd if different:
exec "${SCRIPT_DIR%/}/replay_gmn.sh" "$RUNNUM" "$NEVENTS" 0 "gep5" "$SEG" 1 \
  "$DATA_DIR" "$OUTDIR" "$RUNNUM" "$ANALYZER" "$SBSOFFLINE" "$SBS_REPLAY" "$ANAVER" "$useJLABENV" "$JLABENV" \
  >"$LOG" 2>&1
TASK
chmod +x "$WRAPPER"

# Submit
echo "Submitting SLURM array: $ARRAY_RANGE"
SUBMIT_OUT=$(sbatch \
  --job-name=cdet-replay \
  --array="$ARRAY_RANGE" \
  --partition="${PARTITION:-compute}" \
  --time="${TIME:-02:00:00}" \
  --output="${LOGDIR%/}/slurm-%A_%a.out" \
  --export=ALL,RUNLIST="$RUNLIST",NEVENTS="$NEVENTS",NSEGMENTS="$NSEGMENTS",OUTDIR="$OUTDIR",DATA_DIR="$DATA_DIR",SCRIPT_DIR="$SCRIPT_DIR",ANALYZER="$ANALYZER",SBSOFFLINE="$SBSOFFLINE",SBS_REPLAY="$SBS_REPLAY",ANAVER="$ANAVER",useJLABENV="$useJLABENV",JLABENV="$JLABENV" \
  "$WRAPPER")
echo "$SUBMIT_OUT"

echo ""
echo "Tip: Check status with:"
echo "  squeue -u $USER -n cdet-replay"
echo "After completion, view logs in:"
echo "  $LOGDIR"
