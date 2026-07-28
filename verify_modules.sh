#!/bin/bash
# run as: bash verify_modules.sh --runname 'nov2025'

set -Eeuo pipefail

# -------- paths --------
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -------- logging --------
# Default runname is current date/time
runname="$(date +%Y%m%d_%H%M%S)"
# Parse optional --runname argument
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --runname)
          if [[ "$#" -lt 2 ]]; then
            echo "ERROR: --runname requires an argument" >&2
            exit 2
          fi
          runname="$2"
          shift
          ;;
        -h|--help)
          echo "Usage: bash verify_modules.sh [--runname RUNNAME]"
          exit 0
          ;;
        *)
          echo "ERROR: unknown argument: $1" >&2
          exit 2
          ;;
    esac
    shift
done
logdir="${VERIFY_MODULES_LOGDIR:-$script_dir/verify_modules/logs}"
mkdir -p "$logdir"
logfile="$logdir/verify_modules_${runname}.log"

# Send *everything* to the log
set +e
(
set -Eeuo pipefail

timestamp() {
  date "+%Y-%m-%dT%H:%M:%S%z"
}

echo "=== START $(timestamp) on $(hostname) ==="

# -------- conda init --------
# Ensure conda works in non-interactive shells
if command -v conda >/dev/null 2>&1; then
  :
elif [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
  # typical user install
  # shellcheck disable=SC1090
  source "$HOME/anaconda3/etc/profile.d/conda.sh"
elif [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
  # site install
  # shellcheck disable=SC1091
  source "/opt/conda/etc/profile.d/conda.sh"
else
  echo "WARNING: conda not found in PATH and conda.sh not found; continuing without conda" >&2
fi

# change this to your local path if needed;
Subaru_PFS="${SUBARU_PFS_DIR:-/lustre/work/jingjing.shi/Subaru-PFS}"
if [[ ! -d "$Subaru_PFS" && -d "$script_dir/../../Subaru-PFS" ]]; then
  Subaru_PFS="$(cd "$script_dir/../../Subaru-PFS" && pwd)"
fi

# Prefer the per-run git worktrees created by env_tools/make_run_worktrees.sh
# so we report the git state of exactly what is on PYTHONPATH for this run.
# Falls back to the canonical clones when no worktrees exist for this runname.
MODSETS_ROOT="${MODSETS_ROOT:-$Subaru_PFS/.worktrees}"
run_worktrees="$MODSETS_ROOT/$runname"
if [[ -d "$run_worktrees" ]]; then
  repo_base="$run_worktrees"
  echo "Reporting git state from worktrees for run '$runname': $repo_base"
else
  repo_base="$Subaru_PFS"
  echo "No worktrees at $run_worktrees; reporting canonical clones: $repo_base"
fi

# -------- helper to report git state --------
report_git() {
  local name="$1"
  local repo="$2"
  local exact_tag

  echo ""
  echo "=== ${name} (${repo}) ==="
  # A git worktree's .git is a FILE (gitdir pointer), a normal clone's is a
  # DIR -- accept either so worktrees are reported correctly.
  if [ ! -e "$repo/.git" ]; then
    echo "ERROR: not a git repo or missing: $repo"
    return 1
  fi
  pushd "$repo" >/dev/null

  # What commit/branch/tag is checked out?
  echo "PWD: $(pwd)"
  echo "Remote: $(git remote -v | awk 'NR==1{print $2}')"
  echo "Branch: $(git symbolic-ref --quiet --short HEAD || echo DETACHED)"
  echo "Commit: $(git rev-parse --short HEAD)"

  if exact_tag="$(git describe --tags --exact-match HEAD 2>/dev/null)"; then
    echo "Exact tag at HEAD: $exact_tag"
    popd >/dev/null
    return 0
  fi

  echo "ERROR: HEAD is not exactly at a tag."
  echo "Nearest tag: $(git describe --tags --always 2>/dev/null || echo '<none>')"
  popd >/dev/null
  return 1
}

# -------- report each repo; do not abort on missing/failures --------
git_failures=0
for repo_spec in \
  "datamodel:$repo_base/datamodel" \
  "pfs_utils:$repo_base/pfs_utils" \
  "ics_cobraOps:$repo_base/ics_cobraOps" \
  "ics_cobraCharmer:$repo_base/ics_cobraCharmer" \
  "ets_fiberalloc:$repo_base/ets_fiberalloc" \
  "pfs_instdata:$repo_base/pfs_instdata"
do
  repo_name="${repo_spec%%:*}"
  repo_path="${repo_spec#*:}"
  if ! report_git "$repo_name" "$repo_path"; then
    git_failures=$((git_failures + 1))
  fi
done

echo ""
echo "Git tag verification failures: $git_failures"

echo ""
echo "========================================================="
echo "Running import_modules.py"
echo "CWD before run: $(pwd)"
cd "$script_dir/verify_modules/"

# Print env to the log (helps debug conda)
echo "Environment snapshot:"
echo "  PATH=$PATH"
echo "  CONDA_PREFIX=${CONDA_PREFIX:-<unset>}"
echo "  PFS_INSTDATA_DIR=${PFS_INSTDATA_DIR:-<unset>}"

python -V
if python import_modules.py; then
  module_rc=0
else
  module_rc=$?
fi

echo "import_modules.py exit code: $module_rc"
echo "=== END $(timestamp) ==="
if [[ "$git_failures" -gt 0 || "$module_rc" -ne 0 ]]; then
  exit 1
fi
exit 0
) 2>&1 | tee -a "$logfile"
script_rc=${PIPESTATUS[0]}
exit "$script_rc"
