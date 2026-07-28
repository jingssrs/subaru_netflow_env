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

## Consume from any repo

From inside any science repo, run its work against a pinned environment:

```bash
# once per run: create the worktrees for the tags in runs/<run>/modules.txt
bash "$NETFLOW_ENV_DIR/make_run_worktrees.sh" <run>

# every session: activate (self-sources conda; no prior `conda activate` needed)
source "$NETFLOW_ENV_DIR/activate_run.sh" <run>

# then run your repo's code / verification as usual
```

`activate_run.sh` only sets the conda env + `PYTHONPATH` + `PFS_INSTDATA_DIR`,
so it is completely repo-agnostic — the same command works from every repo.

Each repo keeps its own **verification and output tooling** (e.g. `pfs_co_fa`
keeps `src_py/verify_modules.sh`, `make_reprotest_config.sh`,
`compare_observatory.py`) — those know about that repo's configs and outputs.

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

## Reproduce a past run

```bash
bash "$NETFLOW_ENV_DIR/make_run_worktrees.sh" jan2026
source "$NETFLOW_ENV_DIR/activate_run.sh" jan2026
```

The module layer is pinned exactly; non-module deps come from whichever
`base_env` the manifest names.
