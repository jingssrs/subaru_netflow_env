#!/usr/bin/env bash
# make_run_worktrees.sh
#
# Create git worktrees for one observation run, each pinned to the module
# tag recorded in that run's manifest. Worktrees share the canonical
# clone's object store, so this costs only a working-tree checkout per
# module (not a full clone).
#
# Usage:
#   bash $NETFLOW_ENV_DIR/make_run_worktrees.sh <run>
#   bash $NETFLOW_ENV_DIR/make_run_worktrees.sh july2026
#
# Reads:  $NETFLOW_ENV_DIR/runs/<run>/modules.txt
# Creates: $MODSETS_ROOT/<run>/<module>   (default under $SUBARU_PFS_DIR/.worktrees)
#
# Safe to re-run: an existing worktree already at the right tag is left
# alone; one at the wrong tag is reported as an error (remove it yourself).
# ----------------------------------------------------------------------
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/_layout.sh"

run="${1:-}"
if [[ -z "$run" ]]; then
    echo "Usage: bash make_run_worktrees.sh <run>   (e.g. july2026)" >&2
    exit 2
fi

manifest="$RUNS_DIR/$run/modules.txt"
if [[ ! -f "$manifest" ]]; then
    echo "ERROR: manifest not found: $manifest" >&2
    exit 1
fi

echo "==> Run:      $run"
echo "==> Manifest: $manifest"
echo "==> Clones:   $SUBARU_PFS_DIR"
echo "==> Worktrees:$MODSETS_ROOT/$run"
echo

failures=0

# Parse manifest: skip comments/blank lines and the base_env line.
while read -r name tag _rest; do
    [[ -z "${name:-}" || "$name" == \#* ]] && continue
    [[ "$name" == "base_env" ]] && continue

    clone="$SUBARU_PFS_DIR/$name"
    dest="$MODSETS_ROOT/$run/$name"

    echo "--- $name @ $tag ---"

    if [[ ! -d "$clone/.git" ]]; then
        echo "  ERROR: canonical clone missing: $clone" >&2
        failures=$((failures + 1))
        continue
    fi

    # Make sure the tag is present locally.
    git -C "$clone" fetch --tags --force --quiet || {
        echo "  WARN: 'git fetch --tags' failed for $name (offline?); using local tags" >&2
    }

    if ! git -C "$clone" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
        echo "  ERROR: tag '$tag' not found in $clone" >&2
        failures=$((failures + 1))
        continue
    fi

    want_sha="$(git -C "$clone" rev-parse "refs/tags/$tag^{commit}")"

    if [[ -d "$dest/.git" || -f "$dest/.git" ]]; then
        have_sha="$(git -C "$dest" rev-parse HEAD 2>/dev/null || echo none)"
        if [[ "$have_sha" == "$want_sha" ]]; then
            echo "  OK: already checked out at $tag"
        else
            echo "  ERROR: worktree exists at a different commit ($have_sha != $want_sha)." >&2
            echo "         Remove it first: git -C '$clone' worktree remove '$dest'" >&2
            failures=$((failures + 1))
        fi
        continue
    fi

    mkdir -p "$MODSETS_ROOT/$run"
    # Detached worktree at the exact tag.
    git -C "$clone" worktree add --detach "$dest" "refs/tags/$tag"
    echo "  created: $dest"
done < "$manifest"

echo
if [[ "$failures" -gt 0 ]]; then
    echo "==> Done with $failures failure(s)." >&2
    exit 1
fi
echo "==> All worktrees for '$run' are ready."
echo "    Activate with:  source $NETFLOW_ENV_DIR/activate_run.sh $run"
