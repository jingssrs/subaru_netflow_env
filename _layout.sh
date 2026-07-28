#!/usr/bin/env bash
# _layout.sh
#
# Shared configuration + helpers for the standalone netflow env toolkit.
# Sourced by the other scripts in this directory.
#
# This toolkit is repo-independent: the conda base envs and the Subaru-PFS
# module worktrees it manages are machine-global, and the run manifests live
# here (runs/) alongside the scripts. Any science repo consumes it by sourcing
# activate_run.sh from here (see README.md).
#
# All paths can be overridden via environment variables.
# ----------------------------------------------------------------------

# --- Canonical clones of the Subaru-PFS modules -----------------------
# One clone per module; per-run worktrees are created FROM these (cheap).
: "${SUBARU_PFS_DIR:=/lustre/work/jingjing.shi/Subaru-PFS}"

# --- Where per-run worktrees are created ------------------------------
# Each run gets its own subdir: $MODSETS_ROOT/<run>/<module>
: "${MODSETS_ROOT:=${SUBARU_PFS_DIR}/.worktrees}"

# --- Root of this toolkit = the directory this file lives in ----------
if [[ -z "${NETFLOW_ENV_DIR:-}" ]]; then
    _layout_self="${BASH_SOURCE[0]}"
    NETFLOW_ENV_DIR="$(cd "$(dirname "$_layout_self")" && pwd)"
fi

# --- Where run manifests + base specs are recorded --------------------
: "${RUNS_DIR:=${NETFLOW_ENV_DIR}/runs}"
: "${BASE_DIR:=${NETFLOW_ENV_DIR}/base}"

# --- Per-run modules, in a fixed order --------------------------------
# Modules whose git tag typically changes each run. (opdb / ics_fpsActor /
# ics_utils are one-time installs -> they live in the base conda env.)
PFS_MODULES=(
    datamodel
    pfs_utils
    ics_cobraOps
    ics_cobraCharmer
    ets_fiberalloc
    pfs_instdata
)

# --- Module -> PYTHONPATH sub-directory -------------------------------
#   .../<module>/python/...            for most,
#   .../ets_fiberalloc/ets_fiber_assigner/...  -> package sits at repo root.
# "." means "add the worktree root itself to PYTHONPATH".
pfs_pypath_subdir() {
    case "$1" in
        ets_fiberalloc) echo "." ;;
        *)              echo "python" ;;
    esac
}

# pfs_instdata is a DATA package consumed via PFS_INSTDATA_DIR (set by
# activate_run.sh to the worktree root) rather than imported.
pfs_is_instdata() { [[ "$1" == "pfs_instdata" ]]; }
