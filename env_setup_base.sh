#!/bin/bash
# env_setup_base.sh
#
# Activate a shared FROZEN base env, the same way env_setup.sh activates
# netflow-env. Anyone on the cluster who can read jingjing's anaconda3 can
# source this.
#
#   source env_setup_base.sh            # -> netflow-base-2026-07 (default)
#   source env_setup_base.sh 2026-07    # -> netflow-base-<version>
#
# NOTE: this activates ONLY the base conda env (no Subaru-PFS modules).
#       For an actual observation run, use env_tools/activate_run.sh <run>,
#       which activates the base AND puts the run's module worktrees on
#       PYTHONPATH.

ver="${1:-2026-07}"

source /home/jingjing.shi/anaconda3/etc/profile.d/conda.sh

# Deactivate any existing environments
conda deactivate 2>/dev/null
conda deactivate 2>/dev/null

# Activate the target frozen base
conda activate "netflow-base-${ver}"
export PYTHONNOUSERSITE=1
