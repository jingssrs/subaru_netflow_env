#!/usr/bin/env bash
# strip_pfs_from_base.sh
#
# Remove any pip-installed Subaru-PFS modules from a FROZEN base env, so the
# per-run git worktrees (on PYTHONPATH) are the single source of truth. Only
# the per-run PFS modules are touched -- every real dependency, and one-time
# installs like opdb, are left alone. After stripping, the base's recorded
# lock files are refreshed to match.
#
# Usage:
#   bash $NETFLOW_ENV_DIR/strip_pfs_from_base.sh <base-version>            # do it
#   bash $NETFLOW_ENV_DIR/strip_pfs_from_base.sh --dry-run <base-version>  # just show
#
#   e.g.  bash $NETFLOW_ENV_DIR/strip_pfs_from_base.sh 2026-07
# ----------------------------------------------------------------------
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/_layout.sh"

dry_run=0
if [[ "${1:-}" == "--dry-run" ]]; then dry_run=1; shift; fi

version="${1:-}"
if [[ -z "$version" ]]; then
    echo "Usage: bash strip_pfs_from_base.sh [--dry-run] <base-version>   (e.g. 2026-07)" >&2
    exit 2
fi

env_name="netflow-base-$version"
dest="$BASE_DIR/$env_name"

if ! conda env list | awk '{print $1}' | grep -qx "$env_name"; then
    echo "ERROR: conda env '$env_name' not found." >&2
    exit 1
fi

# Pip distribution names of the per-run PFS modules (NOT opdb, which is
# a one-time base install and must stay). Matched case-insensitively and
# tolerant of '.', '-', '_' separators.
_pfs_dist='^(pfs[._-]utils|pfs[._-]datamodel|pfs[._-]instdata|ics[._-]cobraops|ics[._-]cobracharmer|ets[._-]?fiber[._-]?assigner|ets[._-]?fiberalloc)$'

echo "==> Scanning '$env_name' for pip-installed PFS modules..."
mapfile -t hits < <(
    conda run -n "$env_name" python -m pip list --format=freeze 2>/dev/null \
        | sed 's/==.*//' \
        | grep -iE "$_pfs_dist" || true
)

if [[ "${#hits[@]}" -eq 0 ]]; then
    echo "    None found -- '$env_name' is already PFS-free. Nothing to do."
    exit 0
fi

echo "    Will remove:"
printf '      %s\n' "${hits[@]}"

if [[ "$dry_run" -eq 1 ]]; then
    echo "==> Dry run: no changes made."
    exit 0
fi

echo "==> Uninstalling from '$env_name'..."
conda run -n "$env_name" python -m pip uninstall -y "${hits[@]}"

# --- refresh the recorded lock files so they match the stripped env -----
if [[ -d "$dest" ]]; then
    echo "==> Refreshing recorded locks in $dest"
    conda env export -n "$env_name"                  > "$dest/environment.yml"
    conda env export -n "$env_name" --no-builds      > "$dest/environment.portable.yml"
    conda list       -n "$env_name" --explicit       > "$dest/conda_spec.txt"
    conda run        -n "$env_name" python -m pip freeze > "$dest/requirements.txt"
    {
        echo "# stripped PFS modules: ${hits[*]}"
        echo "# stripped at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >> "$dest/META.txt"
else
    echo "    (no recorded base dir at $dest -- skipping lock refresh)"
fi

echo
echo "==> Done. Re-verify that run modules now resolve to the worktrees:"
echo "    source $NETFLOW_ENV_DIR/activate_run.sh <run>"
echo "    bash \"\$NETFLOW_ENV_DIR/verify_modules.sh\" --runname '<run>_check'"
