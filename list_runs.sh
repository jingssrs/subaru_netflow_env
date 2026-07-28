#!/usr/bin/env bash
# list_runs.sh
#
# Show every recorded run and its pinned environment at a glance:
# the base conda env, each module's git tag, and whether the run's
# worktrees currently exist on disk.
#
# Usage:
#   bash $NETFLOW_ENV_DIR/list_runs.sh            # all runs
#   bash $NETFLOW_ENV_DIR/list_runs.sh july2026   # one run
# ----------------------------------------------------------------------
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/_layout.sh"

show_run() {
    local run="$1"
    local manifest="$RUNS_DIR/$run/modules.txt"
    [[ -f "$manifest" ]] || { echo "  (no manifest: $manifest)"; return; }

    local base_env="" name tag _rest
    echo "=== $run ==="
    while read -r name tag _rest; do
        [[ -z "${name:-}" || "$name" == \#* ]] && continue
        if [[ "$name" == "base_env" ]]; then
            base_env="$tag"; continue
        fi
        local wt="$MODSETS_ROOT/$run/$name" mark="   (worktree missing)"
        if [[ -d "$wt/.git" || -f "$wt/.git" ]]; then mark=""; fi
        printf "    %-18s %-12s%s\n" "$name" "$tag" "$mark"
    done < "$manifest"
    printf "    %-18s %s\n" "base_env" "${base_env:-<none>}"

    # Is the base recorded?
    if [[ -n "$base_env" && -d "$BASE_DIR/$base_env" ]]; then
        echo "    base frozen: yes ($BASE_DIR/$base_env)"
    else
        echo "    base frozen: NO  (run freeze_base_env.sh)"
    fi
    echo
}

if [[ -n "${1:-}" ]]; then
    show_run "$1"
    exit 0
fi

if [[ ! -d "$RUNS_DIR" ]]; then
    echo "No runs recorded yet ($RUNS_DIR does not exist)."
    exit 0
fi

found=0
for d in "$RUNS_DIR"/*/; do
    [[ -d "$d" ]] || continue
    show_run "$(basename "$d")"
    found=1
done
[[ "$found" -eq 1 ]] || echo "No runs recorded yet under $RUNS_DIR."
