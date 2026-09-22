# Producing CDet ROOT Files with `jlab-HPC`

This guide documents the CDet replay workflow on the `cdet` branch of the
`jlab-HPC` repository (also referred to locally as `gocdethpc`). It describes
the currently maintained SWIF2 path:

```text
submit-many-cdet-jobs.sh (optional multi-run wrapper)
    -> submit-cdet-jobs.sh
        -> run-cdet-replay.sh
            -> SBS-replay/replay/replay_CDet.C
                -> cdet_<run>_*.root
```

The submit script finds/stages raw EVIO files and creates jobs. The run script
sets up Analyzer and SBS-offline, compiles `replay_CDet.C` in a private build
directory for each job, runs the replay, and copies the resulting ROOT file to
the requested output directory.

## 1. Requirements

Run these scripts on a Jefferson Lab machine with access to:

- SWIF2 and the JLab batch farm (for normal production), or an ifarm host for
  local testing;
- the GEp raw-data storage under `/mss/halla/sbs/GEp/raw` and
  `/cache/halla/sbs/GEp/raw`;
- working Analyzer, SBS-offline, and SBS-replay installations;
- an SBS-replay checkout containing `replay/replay_CDet.C`, its output
  definitions, cut definitions, and database files;
- a writable output location, normally under `/volatile/halla/sbs/$USER`.

The software versions used to build SBS-offline must be compatible with the
Analyzer/ROOT environment selected in `setenv.sh`.

## 2. Obtain the correct branch

```bash
git clone git@github.com:btspaude/jlab-HPC.git
cd jlab-HPC
git checkout cdet
```

If the repository already exists:

```bash
cd /path/to/jlab-HPC
git checkout cdet
git pull origin cdet
```

## 3. Configure `setenv.sh`

Edit `setenv.sh` before submitting anything. At minimum, set these paths for
your account:

```bash
export SCRIPT_DIR=/path/to/jlab-HPC
export SBSOFFLINE=/path/to/sbs_devel/install
export SBS_REPLAY=/path/to/SBS-replay
```

The default and recommended environment uses the Hall A module files:

```bash
ANAVER='1.7.12-sbs6'
useJLABENV=0
```

When `useJLABENV=0`, `ANAVER` selects the Analyzer module and `ANALYZER` is not
used. If `useJLABENV=1`, set both `JLABENV` and `ANALYZER` to compatible,
existing installations.

`submit-cdet-jobs.sh` also expects `OUT_DIR`, but the current `setenv.sh` does
not define it. Export it before submitting, or add it to your personal copy of
`setenv.sh`:

```bash
export OUT_DIR=/volatile/halla/sbs/$USER/cdet
mkdir -p "$OUT_DIR"
```

Do not copy another user's paths unchanged. In particular, the checked-in
`setenv.sh` and `submit-many-cdet-jobs.sh` contain account-specific paths that
must be changed for a different user.

## 4. Replay one run

The single-run interface is:

```text
./submit-cdet-jobs.sh RUN NEVENTS MIN_SEGMENT MAX_SEGMENT RUN_ON_IFARM
```

Arguments:

| Argument | Meaning |
|---|---|
| `RUN` | GEp run number |
| `NEVENTS` | Events to process per replay job; use `-1` for all events |
| `MIN_SEGMENT` | First EVIO segment number |
| `MAX_SEGMENT` | Last EVIO segment number, inclusive |
| `RUN_ON_IFARM` | `0` submits through SWIF2; `1` runs serially on the current ifarm |

For example, submit segments 0 through 100 of run 5710 and process all events:

```bash
./submit-cdet-jobs.sh 5710 -1 0 100 0
```

The script displays the workflow name and output path and asks whether they are
correct. Because the workflow name is initially blank, answer `n` and provide
a unique workflow name and your output directory:

```text
Do they look good? [y/n] n
Enter desired workflowname : cdet_5710_my_replay
Enter desired outdirpath   : /volatile/halla/sbs/<username>/cdet
```

The script creates and starts the workflow automatically. Use a new workflow
name when repeating a production replay unless you deliberately intend to
operate on an existing workflow.

### Small ifarm test

Before launching a large workflow, test one segment and a limited number of
events interactively:

```bash
./submit-cdet-jobs.sh 5710 10000 0 0 1
```

With `RUN_ON_IFARM=1`, no SWIF2 workflow is created. The replay runs in the
current working directory. This is useful for validating paths, database
selection, compilation, and output before production submission.

## 5. Replay several runs

Place one run number per line in a text file. Blank lines and lines beginning
with `#` are ignored:

```text
# cross-target calibration runs
4344
5710
6077
```

Before using the wrapper, edit this line in `submit-many-cdet-jobs.sh` so it
points to your own volatile directory:

```bash
OUTDIR="/volatile/halla/sbs/$USER/cdet"
```

Then run:

```bash
./submit-many-cdet-jobs.sh my_runs.txt calibration_v1
```

For each run, the wrapper creates a workflow named
`cdet_<run>_calibration_v1` and calls:

```bash
./submit-cdet-jobs.sh <run> -1 0 100 0
```

Therefore, the current wrapper always requests all events and segment numbers
0 through 100. To use different event or segment limits, edit that invocation
or submit each run directly with `submit-cdet-jobs.sh`.

## 6. What each job does

For a requested segment `N`, `submit-cdet-jobs.sh` looks for:

```text
gep5_<run>.evio.0.N
```

It checks the MSS copy and asks SWIF2 to stage the corresponding cache/MSS
input. Jobs for segments greater than zero also stage stream 0, segment 0,
which supplies the initial run information needed by the replay.

`run-cdet-replay.sh` then:

1. loads the selected Analyzer environment;
2. sources `SBSOFFLINE/bin/sbsenv.sh`;
3. sets `ANALYZER_CONFIGPATH`, `DB_DIR`, `OUT_DIR`, and `LOG_DIR`;
4. copies the SBS `.rootrc` into the job working directory;
5. creates a job-private ACLiC directory;
6. compiles and loads `${SBS_REPLAY}/replay/replay_CDet.C+`;
7. calls `replay_CDet(run, nevents, firstevent, "gep5", segment, 1)`;
8. copies every generated `cdet_<run>_*.root` file into
   `<outdir>/rootfiles/`.

The job-private compilation directory prevents simultaneous jobs from writing
the same ACLiC products into the shared SBS-replay checkout.

`replay_CDet.C` currently requests streams 0 through 2. Missing candidate
stream files are skipped by `MultiFileRun`, but the submit script's initial
existence test is specifically for stream 0.

## 7. Output files

Successful files are copied to:

```text
<outdir>/rootfiles/
```

For a full-segment replay, the usual name is similar to:

```text
cdet_5710_stream0_2_seg0_0.root
```

When a positive event limit is supplied, the filename also includes the first
event and requested event count. Exact naming is controlled by
`SBS_REPLAY/replay/replay_CDet.C`.

Confirm output after the jobs finish:

```bash
find "$OUT_DIR/rootfiles" -maxdepth 1 -name 'cdet_5710_*.root' -ls
```

## 8. Monitor and manage SWIF2 workflows

```bash
swif2 status cdet_5710_my_replay
swif2 retry-jobs cdet_5710_my_replay -problem SLURM_NODE_FAIL
swif2 retry-jobs cdet_5710_my_replay -problem SLURM_FAILED
```

To cancel and delete a workflow:

```bash
swif2 cancel cdet_5710_my_replay -delete
```

The repository also contains `misc/swif2-retry.sh`, which runs a workflow and
retries jobs with the two failure types shown above.

## 9. Validation checklist

Before treating a replay as production-ready, verify:

- `setenv.sh` points to your `jlab-HPC`, SBS-offline install, and SBS-replay
  checkout;
- the SBS-replay branch and database constants are the versions you intend to
  use;
- `${SBS_REPLAY}/replay/replay_CDet.C` exists;
- the selected Analyzer environment matches the SBS-offline build;
- the raw run and requested segments exist;
- a one-segment ifarm test produces a readable ROOT file;
- the production workflow finishes without failed or abandoned jobs;
- the expected number of files appears under `<outdir>/rootfiles/`;
- the output tree contains the CDet and ECal variables needed by the downstream
  analysis.

## 10. Common problems

### `SCRIPT_DIR`, `SBSOFFLINE`, or `SBS_REPLAY` is invalid

Correct the corresponding entry in `setenv.sh`. `SBSOFFLINE` must be the
installation prefix containing `bin/sbsenv.sh`, not merely the source tree.

### The workflow name is empty

The single-run script initializes `workflowname` as blank. At its prompt,
answer `n` and enter a workflow name before a farm submission.

### A segment is silently not submitted

The submit script only enters its submission block when this file exists:

```text
/mss/halla/sbs/GEp/raw/gep5_<run>.evio.0.<segment>
```

Check the run number, segment range, raw-data location, and file availability.

### The replay reports that no ROOT output was produced

Inspect the job output for an Analyzer compilation/runtime error, a missing raw
file, or incorrect SBS-replay configuration. `run-cdet-replay.sh` exits with an
error when no `cdet_<run>_*.root` file exists in the job directory.

### ROOT/ACLiC compilation fails

Confirm that the active Analyzer/ROOT module is the environment used to build
SBS-offline, and that `source "$SBSOFFLINE/bin/sbsenv.sh"` succeeds.

### Output goes to another user's directory

Update both `OUT_DIR` and the hard-coded `OUTDIR` in
`submit-many-cdet-jobs.sh`. The checked-in versions currently reflect a
specific user's setup.

## 11. Scripts not recommended for this workflow

The repository contains experimental SLURM compatibility scripts. Their
interfaces and replay commands do not currently match the maintained CDet
SWIF2 chain in every detail. Use `submit-cdet-jobs.sh` (or
`submit-many-cdet-jobs.sh`) with `run-cdet-replay.sh` unless the SLURM scripts
have first been reviewed and adapted for the target system.

