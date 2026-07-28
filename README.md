# subaru_netflow_env — shared, reproducible netflow environments

Standalone toolkit that defines and activates per-run environments for the
Subaru-PFS netflow workflow, shared across all science repos that use it
(`pfs_co_fa`, and your other two repos).

## Model

Two layers, changing on different cadences:

- **Base layer** — one shared, frozen conda env (`netflow-base-<version>`)
  holding every conda/pip dependency *except* the Subaru-PFS modules. Lives in
  a team-readable conda `envs_dir`, so any user/repo can `conda activate` it.
- **Module layer** — the Subaru-PFS modules, pinned per run to git tags and put
  on `PYTHONPATH` via git worktrees. Pure Python, so no `pip install` and no
  mutation of the base env.

A run = a base pointer + a set of git tags, recorded in `runs/<run>/modules.txt`.
Both the base envs and the worktrees are **machine-global**, so this toolkit is
not tied to any one repo.

## Layout

```
subaru_netflow_env/
  _layout.sh              shared config (paths, module list, PYTHONPATH map)
  make_run_worktrees.sh   create tagged worktrees for a run
  activate_run.sh         activate base env + put run's modules on PYTHONPATH
  freeze_base_env.sh      create + record the shared frozen base conda env
  strip_pfs_from_base.sh  remove pip-installed PFS modules from a frozen base
  list_runs.sh            show every recorded run + its tags
  env_setup_base.sh       activate the base env only (mirror of env_setup.sh)
  runs/<run>/modules.txt  per-run manifest (base pointer + module tags)
  base/netflow-base-<v>/  frozen base specs (environment.yml, locks, signature)
```

Override any path via env vars: `SUBARU_PFS_DIR` (canonical module clones),
`MODSETS_ROOT` (worktree location), `NETFLOW_ENV_DIR` (this toolkit's root),
`CONDA_SH` (conda init script).

## Install once (per cluster)

```bash
git clone <this-repo-url> /lustre/work/jingjing.shi/subaru_netflow_env
# add to your shell rc so every repo/session can find it:
export NETFLOW_ENV_DIR=/lustre/work/jingjing.shi/subaru_netflow_env
```

## Using a run (everyone / teammates)

Once a run has been **prepared** (its base env frozen and its worktrees created
— done once by the maintainer, see "Preparing a run" below), anyone just
activates it and works. This is identical for the already-set-up runs
(`nov2025`, `jan2026`, `july2026`) and for any future run.

**One-time per user:**

```bash
# in your ~/.bashrc, so every session/repo finds the toolkit:
export NETFLOW_ENV_DIR=/lustre/work/jingjing.shi/subaru_netflow_env
```

You also need read access to two shared, machine-global things the maintainer
set up (granted via ACLs, e.g. pfs_co_fa/setup_shared_access.sh): the base
conda env (in the maintainer's `anaconda3/envs`) and the worktrees (under
`$SUBARU_PFS_DIR/.worktrees`). Nothing to copy or build.

**Every session, from any repo:**

```bash
# see which runs exist
bash "$NETFLOW_ENV_DIR/list_runs.sh"

# activate one -- sets the run's base conda env + PYTHONPATH + PFS_INSTDATA_DIR
# (self-sources conda; no prior `conda activate` needed)
source "$NETFLOW_ENV_DIR/activate_run.sh" <run>          # e.g. july2026

# optional sanity check: modules should resolve to the worktrees
bash "$NETFLOW_ENV_DIR/verify_modules.sh" --runname '<run>_check'

# then run your repo's own code as usual
```

That is the whole workflow for users — **no worktree creation, no freezing**;
those are already done. `activate_run.sh` is repo-agnostic, so the same command
works from every repo.

## Preparing a run (maintainer, once per run)

Only the person setting up a run does this; afterwards everyone just activates
it as above. Works the same for a brand-new future run.

```bash
# 1. record the run's module tags (follow the observatory's tags for the run)
$EDITOR "$NETFLOW_ENV_DIR/runs/<run>/modules.txt"

# 2. make sure the base env is current (freeze a new one only if it drifted --
#    see "Check whether the base drifted" and "First-time base setup" below)

# 3. create the tagged worktrees for the run
bash "$NETFLOW_ENV_DIR/make_run_worktrees.sh" <run>

# 4. (recommended) activate + verify, then commit runs/<run>/modules.txt
source "$NETFLOW_ENV_DIR/activate_run.sh" <run>
bash   "$NETFLOW_ENV_DIR/verify_modules.sh" --runname '<run>'
```

`verify_modules.sh` lives here too — it checks the shared Subaru-PFS stack and
worktrees, so every repo uses the same one. Each repo keeps only its own
**output tooling** that knows about that repo's configs/outputs (e.g.
`pfs_co_fa` keeps `env_tools/make_reprotest_config.sh` and
`env_tools/compare_observatory.py`).

## First-time base setup

```bash
# create the frozen base directly in a team-readable envs dir + record locks
conda activate netflow-env
CONDA_ENVS_ROOT=/home/jingjing.shi/anaconda3/envs \
    bash "$NETFLOW_ENV_DIR/freeze_base_env.sh" 2026-07
bash "$NETFLOW_ENV_DIR/strip_pfs_from_base.sh" 2026-07   # if PFS modules leaked in
```

## Check whether the base drifted (before a new run)

```bash
conda activate netflow-env
bash "$NETFLOW_ENV_DIR/freeze_base_env.sh" --check 2026-07
```

- **UNCHANGED** — your working env still matches `netflow-base-2026-07`. Nothing
  to do; reuse it and just record the run's module tags.
- **CHANGED** (prints a diff, exits non-zero) — the deps have moved since that
  base was frozen. Cut a **new** base version and point the new run's manifest
  at it (leave the old base untouched so past runs stay reproducible):

  ```bash
  # freeze the current working env as a new base (pick a new version label)
  CONDA_ENVS_ROOT=/home/jingjing.shi/anaconda3/envs \
      bash "$NETFLOW_ENV_DIR/freeze_base_env.sh" 2026-10
  bash "$NETFLOW_ENV_DIR/strip_pfs_from_base.sh" 2026-10   # if PFS modules leaked in

  # then set base_env in the new run's manifest:
  #   base_env   netflow-base-2026-10
  ```

## Reproduce a past run

```bash
bash "$NETFLOW_ENV_DIR/make_run_worktrees.sh" jan2026
source "$NETFLOW_ENV_DIR/activate_run.sh" jan2026
```

The module layer is pinned exactly; non-module deps come from whichever
`base_env` the manifest names.
