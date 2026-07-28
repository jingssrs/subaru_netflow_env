# Migration — extracting the env layer out of pfs_co_fa

This folder was staged **inside** `pfs_co_fa` because that's the only place the
assistant could write. Finish the extraction by hand:

## 1. Move it out and make it its own git repo

```bash
cd /path/to/PFS_CO_Repo
mv pfs_co_fa/subaru_netflow_env ./subaru_netflow_env
cd subaru_netflow_env
git init && git add -A && git commit -m "Initial standalone netflow env toolkit"
# then push to a remote and clone to a fixed cluster path, e.g.
#   /lustre/work/jingjing.shi/subaru_netflow_env
```

## 2. Point every repo at it

Add to your shell rc (so all repos/sessions see it):

```bash
export NETFLOW_ENV_DIR=/lustre/work/jingjing.shi/subaru_netflow_env
```

Then in each repo, activate a run with:

```bash
bash "$NETFLOW_ENV_DIR/make_run_worktrees.sh" <run>
source "$NETFLOW_ENV_DIR/activate_run.sh" <run>
```

## 3. Clean up the copy left in pfs_co_fa

The generic scripts now live here, so remove the duplicates from
`pfs_co_fa/env_tools/` (the assistant can't delete files). KEEP the
repo-specific ones in pfs_co_fa:

Remove from `pfs_co_fa/env_tools/`:
    _layout.sh  activate_run.sh  make_run_worktrees.sh  freeze_base_env.sh
    strip_pfs_from_base.sh  list_runs.sh  runs/  base/
and `pfs_co_fa/env_setup_base.sh`.

Keep in pfs_co_fa (repo-specific — they know about netflow configs/outputs):
    env_tools/make_reprotest_config.sh
    env_tools/compare_observatory.py
    src_py/verify_modules.sh

```bash
cd pfs_co_fa/env_tools
git rm -r _layout.sh activate_run.sh make_run_worktrees.sh freeze_base_env.sh \
          strip_pfs_from_base.sh list_runs.sh runs base
git rm ../env_setup_base.sh
```

## 4. Update pfs_co_fa's docs

In `pfs_co_fa/observation_run_workflow.md` and any script that referenced
`env_tools/activate_run.sh`, replace with `"$NETFLOW_ENV_DIR/activate_run.sh"`.
`make_reprotest_config.sh` still sources `_layout.sh` from its own dir — since
it stays in pfs_co_fa but `_layout.sh` moves out, either keep a copy of
`_layout.sh` in pfs_co_fa/env_tools, or have it source
`"$NETFLOW_ENV_DIR/_layout.sh"`.

## Note on the two repo-specific scripts

`make_reprotest_config.sh` and `compare_observatory.py` currently `source
_layout.sh` (for `MODSETS_ROOT`/`RUNS_DIR`). After extraction, point that
`source` at `"$NETFLOW_ENV_DIR/_layout.sh"` so they keep working from
pfs_co_fa.
