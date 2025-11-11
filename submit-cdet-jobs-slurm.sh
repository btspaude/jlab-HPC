#!/usr/bin/env bash
# submit-cdet-jobs-slurm.sh
#
# SLURM job-array wrapper to submit CDet/GMn-style replay jobs.
# Converts the old swif2-style "workflow" into a native SLURM array with per-run tasks.
#
# Usage (example):
#   ./submit-cdet-jobs-slurm.sh -r runlist.txt -o /path/to/out -l /path/to/logs \
#       -s /path/to/replay_script.sh -n 500000 --partition=general --time=02:00:00
#
# Notes:
# - Expects a text runlist with one run number per line (comments and blank lines allowed).
# - Each array task picks its run via SLURM_ARRAY_TASK_ID.
# - Replace the REPLAY COMMAND section with your experiment's invocation.
#
set -euo pipefail
IFS=$'\n\t'

# -------- Defaults (override via flags) -------- #
RUNLIST=
OUTDIR=${OUTDIR:-$PWD/out}
LOGDIR=${LOGDIR:-$PWD/logs}
REPLAY_SCRIPT=
NEVENTS=0                     # 0 = all
CONFIG=${CONFIG:-gep5}        # example: 'gep5' (change for your config)
SEGMENT=${SEGMENT:-0}         # segment/chunk index if applicable
USE_IFARM=${USE_IFARM:-0}     # 1 to force local/interactive (no sbatch), else array
# SLURM defaults
PARTITION=${PARTITION:-general}
TIME=${TIME:-02:00:00}
ACCOUNT=${ACCOUNT:-}
CONSTRAINT=${CONSTRAINT:-}
QOS=${QOS:-}
DRYRUN=${DRYRUN:-0}

# -------- Helper: usage -------- #
usage() {
  cat <<EOF
Usage: $0 -r RUNLIST -s REPLAY_SCRIPT [-n NEVENTS] [-o OUTDIR] [-l LOGDIR]
            [--partition NAME] [--time HH:MM:SS] [--account NAME]
            [--constraint STR] [--qos NAME] [--dry-run] [--ifarm]

Required:
  -r, --runlist FILE         File containing run numbers (one per line).
  -s, --script  FILE         Replay script to execute for each run.

Optional:
  -n, --nevents N            Number of events (default: 0 = all).
  -o, --outdir  DIR          Output directory (default: ./out).
  -l, --logdir  DIR          Log directory (default: ./logs).
      --partition NAME       SLURM partition (default: general).
      --time HH:MM:SS        Walltime (default: 02:00:00).
      --account NAME         SLURM account.
      --constraint STR       SLURM constraint.
      --qos NAME             SLURM QoS.
      --dry-run              Print what would run but don't submit/execute.
      --ifarm                Run in a for-loop locally (no sbatch).

Environment (optional):
  DATA_DIR, ANALYZER, SBSOFFLINE, SBS_REPLAY, ANAVER, useJLABENV, JLABENV
  CONFIG, SEGMENT can also be set via env or flags.

EOF
}

# -------- Parse flags -------- #
short_opts="r:s:n:o:l:"
long_opts="runlist:,script:,nevents:,outdir:,logdir:,partition:,time:,account:,constraint:,qos:,dry-run,ifarm"
PARSED=$(python3 - <<'PY'
import sys, shlex
args = sys.argv[1:]
short = "r:s:n:o:l:"
long = ["runlist=", "script=", "nevents=", "outdir=", "logdir=", "partition=", "time=", "account=", "constraint=", "qos=", "dry-run", "ifarm"]
out = []
i=0
while i < len(args):
    a = args[i]
    if a in ("-r","--runlist","-s","--script","-n","--nevents","-o","--outdir","-l","--logdir","--partition","--time","--account","--constraint","--qos"):
        key = a
        i += 1
        if i >= len(args): print("Missing value for", key, file=sys.stderr); sys.exit(2)
        out += [key, args[i]]
    elif a in ("--dry-run","--ifarm"):
        out += [a]
    else:
        out += [a]
    i += 1
print(" ".join(shlex.quote(x) for x in out))
PY
) || { echo "Flag parsing failed"; exit 2; }
eval set -- "$PARSED"

while (( "$#" )); do
  case "$1" in
    -r|--runlist) RUNLIST="$2"; shift 2;;
    -s|--script)  REPLAY_SCRIPT="$2"; shift 2;;
    -n|--nevents) NEVENTS="$2"; shift 2;;
    -o|--outdir)  OUTDIR="$2"; shift 2;;
    -l|--logdir)  LOGDIR="$2"; shift 2;;
    --partition)  PARTITION="$2"; shift 2;;
    --time)       TIME="$2"; shift 2;;
    --account)    ACCOUNT="$2"; shift 2;;
    --constraint) CONSTRAINT="$2"; shift 2;;
    --qos)        QOS="$2"; shift 2;;
    --dry-run)    DRYRUN=1; shift ;;
    --ifarm)      USE_IFARM=1; shift ;;
    --) shift; break;;
    *) break;;
  esac
done

# -------- Validate -------- #
[[ -z "${RUNLIST}" || -z "${REPLAY_SCRIPT}" ]] && { usage; exit 1; }
command -v sbatch >/dev/null 2>&1 || [[ "$USE_IFARM" -eq 1 ]] || { echo "sbatch not found in PATH"; exit 1; }
[[ -f "$RUNLIST" ]] || { echo "Runlist not found: $RUNLIST"; exit 1; }
[[ -x "$REPLAY_SCRIPT" ]] || { echo "Replay script not executable: $REPLAY_SCRIPT"; exit 1; }

mkdir -p "$OUTDIR" "$LOGDIR"

# -------- Build filtered run array -------- #
mapfile -t RUNS < <(grep -E '^[[:space:]]*[0-9]+' "$RUNLIST" | sed -E 's/#.*//' | awk '{print $1}')
NUM_RUNS=${#RUNS[@]}
[[ "$NUM_RUNS" -gt 0 ]] || { echo "No runs found in $RUNLIST"; exit 1; }

echo "Found $NUM_RUNS runs in $RUNLIST"
echo "Output -> $OUTDIR"
echo "Logs   -> $LOGDIR"

# -------- Local loop (ifarm) -------- #
if [[ "$USE_IFARM" -eq 1 ]]; then
  echo "Running locally on ifarm (no SLURM)"
  for idx in "${!RUNS[@]}"; do
    RUNNUM="${RUNS[$idx]}"
    LOG="$LOGDIR/run_${RUNNUM}.log"
    echo "[LOCAL] $REPLAY_SCRIPT $RUNNUM $NEVENTS $CONFIG $SEGMENT"
    if [[ "$DRYRUN" -eq 0 ]]; then
      set +e
      "$REPLAY_SCRIPT" "$RUNNUM" "$NEVENTS" "$CONFIG" "$SEGMENT" "$OUTDIR" >"$LOG" 2>&1
      RC=$?
      set -e
      echo "Run $RUNNUM exit code: $RC (log: $LOG)"
    fi
  done
  exit 0
fi

# -------- SLURM array submission -------- #
ARRAY_RANGE="0-$((NUM_RUNS-1))"

# Build sbatch command
SBATCH_CMD=(sbatch
  --job-name=cdet-replay
  --array="$ARRAY_RANGE"
  --partition="$PARTITION"
  --time="$TIME"
  --output="$LOGDIR/slurm-%A_%a.out"
)

[[ -n "$ACCOUNT"    ]] && SBATCH_CMD+=(--account="$ACCOUNT")
[[ -n "$CONSTRAINT" ]] && SBATCH_CMD+=(--constraint="$CONSTRAINT")
[[ -n "$QOS"        ]] && SBATCH_CMD+=(--qos="$QOS")

# Create the array task wrapper
WRAPPER="$LOGDIR/array_task.sh"
cat > "$WRAPPER" <<'TASK'
#!/usr/bin/env bash
set -euo pipefail
IFS=$'
	'

RUNLIST="${RUNLIST}"
REPLAY_SCRIPT="${REPLAY_SCRIPT}"
NEVENTS="${NEVENTS}"
CONFIG="${CONFIG}"
SEGMENT="${SEGMENT}"
OUTDIR="${OUTDIR}"

# Get run number for this task
IDX="${SLURM_ARRAY_TASK_ID:-0}"
RUNNUM=$(grep -E '^[[:space:]]*[0-9]+' "$RUNLIST" | sed -E 's/#.*//' | awk '{print $1}' | sed -n "$((IDX+1))p")

if [[ -z "${RUNNUM:-}" ]]; then
  echo "Could not resolve run number for index $IDX"
  exit 1
fi

echo "Task $SLURM_ARRAY_TASK_ID -> RUN $RUNNUM"
echo "Executing: $REPLAY_SCRIPT $RUNNUM $NEVENTS $CONFIG $SEGMENT $OUTDIR"

# ---- REPLAY COMMAND (adapt this to your experiment) ----
# Example signature expected by many GMn/CDet wrappers might be:
#   replay_script.sh <runnum> <nevents> <config> <segment> <outdir>
#
"$REPLAY_SCRIPT" "$RUNNUM" "$NEVENTS" "$CONFIG" "$SEGMENT" "$OUTDIR"
TASK
chmod +x "$WRAPPER"

echo "Submitting SLURM array: ${SBATCH_CMD[*]} $WRAPPER"
if [[ "$DRYRUN" -eq 1 ]]; then
  echo "(dry-run) Not submitting."
else
  RUNID=$("${SBATCH_CMD[@]}"           --export=ALL,RUNLIST="$RUNLIST",REPLAY_SCRIPT="$REPLAY_SCRIPT",NEVENTS="$NEVENTS",CONFIG="$CONFIG",SEGMENT="$SEGMENT",OUTDIR="$OUTDIR"           "$WRAPPER")
  echo "$RUNID"
fi
