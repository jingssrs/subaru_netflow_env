#!/usr/bin/env bash
# activate_run.sh
#
# Activate the environment for one observation run:
#   1. activate the shared frozen base conda env named in the run manifest,
#   2. put that run's Subaru-PFS module worktrees on PYTHONPATH,
#   3. set PFS_INSTDATA_DIR to the run's pfs_instdata worktree.
#
# The base conda env is never modified -- all runs share it. The only
# per-run difference is which worktrees are on PYTHONPATH, so any run is
# reproducible from its manifest alone.
#
# MUST be sourced (it changes your current shell):
#   source $NETFLOW_ENV_DIR/activate_run.sh <run>
#   source $NETFLOW_ENV_DIR/activate_run.sh july2026
#
# Prerequisite: worktrees created via make_run_worktrees.sh <run>.
# ----------------------------------------------------------------------

# --- Guard: must be sourced, not executed -----------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: source this script, don't run it:" >&2
    echo "   source $NETFLOW_ENV_DIR/activate_run.sh <run>" >&2
    exit 2
fi

# Use a function so we can 'return' cleanly without killing the shell.
_activate_run() {
    local run="${1:-}"
    if [[ -z "$run" ]]; then
        echo "Usage: source activate_run.sh <run>   (e.g. july2026)" >&2
        return 2
    fi

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=/dev/null
    source "$script_dir/_layout.sh"

    local manifest="$RUNS_DIR/$run/modules.txt"
    if [[ ! -f "$manifest" ]]; then
        echo "ERROR: manifest not found: $manifest" >&2
        return 1
    fi

    # --- read base_env from the manifest ------------------------------
    local base_env="" name tag _rest
    while read -r name tag _rest; do
        [[ -z "${name:-}" || "$name" == \#* ]] && continue
        if [[ "$name" == "base_env" ]]; then base_env="$tag"; fi
    done < "$manifest"

    if [[ -z "$base_env" ]]; then
        echo "ERROR: no 'base_env' line in $manifest" >&2
        return 1
    fi

    # --- conda ---------------------------------------------------------
    local conda_sh="${CONDA_SH:-/home/jingjing.shi/anaconda3/etc/profile.d/conda.sh}"
    if [[ -f "$conda_sh" ]]; then
        # shellcheck source=/dev/null
        source "$conda_sh"
    elif ! command -v conda >/dev/null 2>&1; then
        echo "ERROR: conda not found (looked for $conda_sh). Set CONDA_SH." >&2
        return 1
    fi
    conda deactivate 2>/dev/null || true
    conda deactivate 2>/dev/null || true
    if ! conda activate "$base_env"; then
        echo "ERROR: could not activate base env '$base_env'." >&2
        echo "       Create/record it first (see $NETFLOW_ENV_DIR/freeze_base_env.sh)." >&2
        return 1
    fi
    export PYTHONNOUSERSITE=1

    # --- build PYTHONPATH from this run's worktrees --------------------
    local new_pp="" mod subdir path warn=0
    for mod in "${PFS_MODULES[@]}"; do
        # find the tag for this module in the manifest (for messaging)
        local wt="$MODSETS_ROOT/$run/$mod"
        if [[ ! -d "$wt" ]]; then
            echo "WARN: worktree missing for $mod: $wt" >&2
            echo "      run: bash $NETFLOW_ENV_DIR/make_run_worktrees.sh $run" >&2
            warn=1
            continue
        fi
        subdir="$(pfs_pypath_subdir "$mod")"
        if [[ "$subdir" == "." ]]; then
            path="$wt"
        else
            path="$wt/$subdir"
        fi
        if [[ -d "$path" ]]; then
            new_pp="${new_pp:+$new_pp:}$path"
        fi
        if pfs_is_instdata "$mod"; then
            export PFS_INSTDATA_DIR="$wt"
        fi
    done

    # Prepend so the run's modules win over anything in the base env.
    export PYTHONPATH="${new_pp}${PYTHONPATH:+:$PYTHONPATH}"

    # --- summary -------------------------------------------------------
    echo "== run:            $run"
    echo "== base conda env: $base_env  ($(python -V 2>&1))"
    echo "== PFS_INSTDATA_DIR: ${PFS_INSTDATA_DIR:-<unset>}"
    echo "== PYTHONPATH (run modules prepended):"
    local IFS=':'
    for path in $new_pp; do echo "     $path"; done
    if [[ "$warn" -eq 1 ]]; then
        echo "!! some worktrees were missing -- environment is incomplete." >&2
    fi
    echo "   Verify with: bash \"\$NETFLOW_ENV_DIR/verify_modules.sh\" --runname '$run'"
}

_activate_run "$@"
