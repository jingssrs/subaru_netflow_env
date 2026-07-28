#!/usr/bin/env bash
# freeze_base_env.sh
#
# Create + record an immutable, frozen BASE conda env (all conda/pip deps
# EXCEPT the per-run Subaru-PFS modules). Freezing CLONES your currently
# active working env (e.g. netflow-env) into a new env named
# 'netflow-base-<version>' and records its lock files. Run this only when
# the base actually changes -- not every run. Most runs reuse an existing
# frozen base and change only their module tags.
#
# Usage:
#   # 1. Check whether your working env drifted from the last frozen base:
#   conda activate netflow-env
#   bash $NETFLOW_ENV_DIR/freeze_base_env.sh --check <version>
#
#   # 2. If it changed (or first time), freeze it (clones the ACTIVE env):
#   conda activate netflow-env
#   bash $NETFLOW_ENV_DIR/freeze_base_env.sh <version>      # e.g. 2026-07
#
# Creates: conda env 'netflow-base-<version>'  (activate_run.sh activates this)
#
# To create it directly in a team-readable, shareable location (so you skip
# the later clone-then-remove), set CONDA_ENVS_ROOT to a dir that is also a
# conda envs_dir -- e.g. anaconda3/envs, so the env still resolves by name:
#   CONDA_ENVS_ROOT=/home/jingjing.shi/anaconda3/envs \
#       bash $NETFLOW_ENV_DIR/freeze_base_env.sh 2026-07
#
# Writes into $NETFLOW_ENV_DIR/base/netflow-base-<version>/:
#   environment.yml         full export, exact builds  (exact rebuild)
#   environment.portable.yml  export --no-builds        (cross-platform)
#   conda_spec.txt          conda list --explicit       (URL lock)
#   requirements.txt        pip freeze
#   base_signature.txt      conda list --export minus PFS modules (for --check)
# ----------------------------------------------------------------------
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/_layout.sh"

# Regex of package names to exclude from the base signature: the per-run
# Subaru-PFS modules (they don't belong to the base).
_pfs_grep='datamodel|pfs[._-]utils|pfs[._-]datamodel|pfs[._-]instdata|cobra|ets[._-]fiber|ets_fiber_assigner'

_signature() {
    # A stable name+version listing of the base, excluding PFS modules.
    # Pass conda env selector tokens (e.g. -n NAME or -p PREFIX); none = active.
    conda list "$@" --export 2>/dev/null | grep -v -E "^#" | grep -v -E "$_pfs_grep" | sort
}

_env_exists() {
    conda env list | awk '{print $1}' | grep -qx "$1"
}

mode="freeze"
if [[ "${1:-}" == "--check" ]]; then
    mode="check"; shift
fi

version="${1:-}"
if [[ -z "$version" ]]; then
    echo "Usage: bash freeze_base_env.sh [--check] <version>   (e.g. 2026-07)" >&2
    exit 2
fi

dest="$BASE_DIR/netflow-base-$version"

if [[ -z "${CONDA_PREFIX:-}" ]]; then
    echo "ERROR: no conda env is active. 'conda activate <env>' first." >&2
    exit 1
fi

if [[ "$mode" == "check" ]]; then
    if [[ ! -f "$dest/base_signature.txt" ]]; then
        echo "No frozen base at $dest yet -- nothing to compare. Freeze it."
        exit 0
    fi
    if diff -u "$dest/base_signature.txt" <(_signature); then
        echo "==> Base UNCHANGED vs netflow-base-$version. Reuse it; just record the run manifest."
    else
        echo "==> Base CHANGED vs netflow-base-$version (diff above)." >&2
        echo "    Cut a new version:  bash $NETFLOW_ENV_DIR/freeze_base_env.sh <new-version>" >&2
        exit 3
    fi
    exit 0
fi

# --- freeze --------------------------------------------------------------
env_name="netflow-base-$version"

# Decide where/how to create the env. When CONDA_ENVS_ROOT is set we create
# at that prefix (put it in a team-readable envs_dir so it still resolves by
# name); otherwise a normal named env in the default envs dir.
if [[ -n "${CONDA_ENVS_ROOT:-}" ]]; then
    env_prefix="$CONDA_ENVS_ROOT/$env_name"
    env_ref=(-p "$env_prefix")
    where="$env_prefix"
    remove_hint="conda env remove -p $env_prefix"
    _already() { [[ -d "$env_prefix/conda-meta" ]]; }
    _create()  { conda create --yes --prefix "$env_prefix" --clone "$CONDA_PREFIX"; }
else
    env_ref=(-n "$env_name")
    where="$env_name (default envs dir)"
    remove_hint="conda env remove -n $env_name"
    _already() { _env_exists "$env_name"; }
    _create()  { conda create --yes --name "$env_name" --clone "$CONDA_PREFIX"; }
fi

echo "==> Freezing current env '$CONDA_PREFIX' into frozen env: $where"

# Create the immutable frozen clone (leave it alone if it already exists).
if _already; then
    echo "    already exists -- leaving it untouched (immutable)."
    echo "    (delete it first if you really want to re-freeze: $remove_hint)"
else
    echo "    creating (clone of $CONDA_PREFIX) ..."
    _create
fi

# Record its lock files (targeted, no activation needed).
mkdir -p "$dest"
conda env export "${env_ref[@]}"                     > "$dest/environment.yml"
conda env export "${env_ref[@]}" --no-builds         > "$dest/environment.portable.yml"
conda list       "${env_ref[@]}" --explicit          > "$dest/conda_spec.txt"
conda run        "${env_ref[@]}" python -m pip freeze > "$dest/requirements.txt"
_signature       "${env_ref[@]}"                     > "$dest/base_signature.txt"

{
    echo "# netflow base env snapshot"
    echo "# frozen:      $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# host:        $(hostname)"
    echo "# env name:    $env_name"
    echo "# location:    $where"
    echo "# cloned from: $CONDA_PREFIX"
    echo "# python:      $(conda run "${env_ref[@]}" python -V 2>&1)"
} > "$dest/META.txt"

echo "==> Wrote:"
ls -1 "$dest"
echo
echo "Frozen conda env created: $env_name"
echo "Run manifests reference it as:  base_env  $env_name"
